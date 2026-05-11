import AVFoundation
import Foundation
import WebRTC

enum RealtimeState: String {
    case idle, fetchingSession, connecting, connected, speaking, error, closed
}

@MainActor
final class RealtimeClient: NSObject, ObservableObject {

    // ---- public, observable state ----
    @Published private(set) var state: RealtimeState = .idle
    @Published private(set) var currentCue: String = ""
    @Published private(set) var lastError: String? = nil

    // ---- private internals ----
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoder = RTCDefaultVideoEncoderFactory()
        let videoDecoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoder, decoderFactory: videoDecoder)
    }()

    private let exercise: ExerciseId
    private let targetReps: Int?
    private let athleteName: String?
    private var pc: RTCPeerConnection?
    private var dc: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var pendingEvents: [(event: CoachEvent, requestSpeech: Bool)] = []
    private var transcriptBuffer: String = ""

    /// True while OpenAI is actively producing a response. Sending another
    /// `response.create` while this is true returns
    /// "Conversation already has an active response in progress". We instead
    /// `response.cancel` the in-flight one and queue a single replacement.
    private var isResponding: Bool = false
    /// At most one pending replacement — newer requests collapse into it.
    private var pendingReplacementSpeech: Bool = false

    init(exercise: ExerciseId, targetReps: Int?, athleteName: String? = nil) {
        self.exercise = exercise
        self.targetReps = targetReps
        self.athleteName = athleteName
        super.init()
    }

    deinit {
        // Best-effort teardown if the consumer didn't call close().
        pc?.close()
    }

    // MARK: - Public API

    func connect() async {
        do {
            try await configureAudioSession()

            setState(.fetchingSession)
            let session = try await BackendClient.createRealtimeSession(
                exercise: exercise, targetReps: targetReps, athleteName: athleteName)

            setState(.connecting)
            let pc = makePeerConnection()
            self.pc = pc

            // Mic uplink. We add the track and let WebRTC negotiate; the audio
            // is uploaded continuously, but server VAD is OFF so the model only
            // speaks when we explicitly send response.create.
            attachLocalAudio(to: pc)

            // Data channel for coach events.
            let cfg = RTCDataChannelConfiguration()
            cfg.isOrdered = true
            let dc = pc.dataChannel(forLabel: "oai-events", configuration: cfg)
            dc?.delegate = self
            self.dc = dc

            // Create offer, post SDP to OpenAI, set answer.
            let offer = try await createOffer(pc: pc)
            try await pc.setLocalDescription(offer)
            let answerSdp = try await postSDP(offer.sdp,
                                              clientSecret: session.clientSecret,
                                              model: session.model)
            let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
            try await pc.setRemoteDescription(answer)
        } catch {
            lastError = error.localizedDescription
            setState(.error)
        }
    }

    func sendEvent(_ event: CoachEvent, requestSpeech: Bool = false) {
        guard let dc = dc, dc.readyState == .open else {
            pendingEvents.append((event, requestSpeech))
            return
        }
        do {
            let item = try RealtimeEnvelope.conversationItem(for: event)
            dc.sendData(RTCDataBuffer(data: item, isBinary: false))
            if requestSpeech {
                requestSpeechNow(dc: dc)
            }
        } catch {
            print("[realtime] failed to encode event: \(error)")
        }
    }

    /// Internal helper. Handles the in-flight-response collision by cancelling
    /// the active response and queuing exactly one replacement, so the most
    /// recent cue always wins without piling up duplicate `response.create`s.
    private func requestSpeechNow(dc: RTCDataChannel) {
        if isResponding {
            // A response is mid-stream. Cancel it; on response.done we'll fire
            // a fresh response.create.
            do {
                let cancel = try RealtimeEnvelope.responseCancel()
                dc.sendData(RTCDataBuffer(data: cancel, isBinary: false))
                pendingReplacementSpeech = true
            } catch {
                print("[realtime] failed to encode response.cancel: \(error)")
            }
            return
        }
        do {
            let req = try RealtimeEnvelope.responseCreate()
            dc.sendData(RTCDataBuffer(data: req, isBinary: false))
            isResponding = true
        } catch {
            print("[realtime] failed to encode response.create: \(error)")
        }
    }

    func requestSpeech(reason: String) {
        sendEvent(.coachShouldSpeak(reason: reason), requestSpeech: true)
    }

    func setMicEnabled(_ enabled: Bool) {
        audioTrack?.isEnabled = enabled
    }

    func close() {
        dc?.close()
        pc?.close()
        dc = nil
        pc = nil
        audioTrack = nil
        setState(.closed)
    }

    // MARK: - Internals

    private func setState(_ s: RealtimeState) {
        guard state != s else { return }
        state = s
    }

    private func configureAudioSession() async throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord,
                          mode: .voiceChat,
                          options: [.defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
    }

    private func makePeerConnection() -> RTCPeerConnection {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        // Force-unwrap is safe — factory is a static singleton with valid config.
        return RealtimeClient.factory.peerConnection(with: config,
                                                      constraints: constraints,
                                                      delegate: self)!
    }

    private func attachLocalAudio(to pc: RTCPeerConnection) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = RealtimeClient.factory.audioSource(with: constraints)
        let track = RealtimeClient.factory.audioTrack(with: audioSource, trackId: "spottr-mic")
        audioTrack = track
        pc.add(track, streamIds: ["spottr"])
    }

    private func createOffer(pc: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true"],
                optionalConstraints: nil)
            pc.offer(for: constraints) { sdp, err in
                if let sdp = sdp { cont.resume(returning: sdp) }
                else { cont.resume(throwing: err ?? NSError(domain: "rtc", code: -1)) }
            }
        }
    }

    private func postSDP(_ sdp: String, clientSecret: String, model: String) async throws -> String {
        // GA endpoint. The legacy /v1/realtime auto-asserts an `OpenAI-Beta:
        // realtime=v1` header server-side and now returns
        // "Unknown beta requested: 'realtime'". The GA path is /v1/realtime/calls
        // and uses the model embedded in the ephemeral key — passing model in
        // the query string is also accepted.
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls?model=\(model)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.httpBody = sdp.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "BackendClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "SDP exchange failed: \(txt)"])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    fileprivate func handleServerEvent(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }

        switch type {
        case "error":
            let err = msg["error"] as? [String: Any]
            let m = (err?["message"] as? String) ?? "unknown realtime error"
            // Suppress the "active response in progress" race — we already
            // handle it client-side by cancelling + replacing.
            if (err?["code"] as? String) != "conversation_already_has_active_response" {
                lastError = m
            }
            print("[realtime] error: \(m)")
        case "response.created":
            transcriptBuffer = ""
            currentCue = ""
            isResponding = true
            setState(.speaking)
        // GA event names use `output_audio_transcript` — the legacy
        // `audio_transcript.*` names no longer fire on `gpt-realtime`.
        case "response.output_audio_transcript.delta",
             "response.audio_transcript.delta":
            if let delta = msg["delta"] as? String {
                transcriptBuffer += delta
                currentCue = transcriptBuffer
            }
        case "response.output_audio_transcript.done",
             "response.audio_transcript.done":
            if let final = msg["transcript"] as? String {
                currentCue = final
            }
        case "response.done", "response.cancelled":
            isResponding = false
            setState(.connected)
            // If a newer cue piled up while this one was streaming/cancelling,
            // fire it now.
            if pendingReplacementSpeech, let dc = dc, dc.readyState == .open {
                pendingReplacementSpeech = false
                requestSpeechNow(dc: dc)
            }
        default:
            break
        }
    }

    fileprivate func dataChannelDidOpen() {
        setState(.connected)
        // Initial event: tell the model the set has started.
        sendEvent(.setStarted(exercise: exercise, targetReps: targetReps))
        // Drain anything queued during connect.
        for queued in pendingEvents {
            sendEvent(queued.event, requestSpeech: queued.requestSpeech)
        }
        pendingEvents.removeAll()
    }
}

// MARK: - WebRTC delegate

extension RealtimeClient: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange newState: RTCIceConnectionState) {
        if newState == .failed || newState == .disconnected {
            Task { @MainActor in
                self.lastError = "ICE \(newState.rawValue)"
            }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didOpen dataChannel: RTCDataChannel) {
        Task { @MainActor in
            // The model's data channel — we may already have ours. Either way, set delegate.
            dataChannel.delegate = self
        }
    }

    // Required no-op stubs.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
}

extension RealtimeClient: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor in
            if dataChannel.readyState == .open {
                self.dataChannelDidOpen()
            } else if dataChannel.readyState == .closed {
                self.setState(.closed)
            }
        }
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard !buffer.isBinary,
              let json = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any]
        else { return }
        Task { @MainActor in self.handleServerEvent(json) }
    }
}
