import AVFoundation
import Combine
import CoreVideo
import SwiftUI

/// Stage of the workout session.
///
/// `.waiting` — camera is on, realtime is connecting in the background, but
///   the system has not yet seen the athlete clearly. Nothing fires.
/// `.ready`   — the athlete's whole body has been in frame continuously for a
///   beat. The coach greets them by name so they know they're set, even with
///   the phone across the room. Timer still hasn't started.
/// `.active`  — first rep was detected; timer + counting are now live.
/// `.finished` — set ended (target reached or user pressed End set).
enum WorkoutStage {
    case waiting, ready, active, finished
}

@MainActor
final class WorkoutController: NSObject, ObservableObject, CameraSessionDelegate {

    @Published var snapshot = AnalyzerSnapshot()
    @Published var elapsedMs: Int = 0
    @Published var coachError: String? = nil
    @Published var stage: WorkoutStage = .waiting
    /// Set when the user (or auto-finish) ends the set; the view navigates.
    @Published var didFinish: Bool = false
    @Published var recordingURL: URL? = nil
    @Published var recordingPhotoSaveState: PhotoSaveState = .notRequested
    /// True when the back camera is the active feed (default is the front).
    @Published private(set) var usingBackCamera: Bool = false

    let camera = CameraSession()
    let realtime: RealtimeClient
    let sessionRecorder = SessionRecorder()

    private let exercise: ExerciseId
    private let targetReps: Int
    private let mode: CoachMode
    private let shouldRecordSession: Bool
    private let analyzer: ExerciseAnalyzer
    private let detector = PoseDetector()
    private let visualFrameSampler = VisualFrameSampler(interval: 3.0)
    private let detectionQueue = DispatchQueue(label: "com.spottr.pose", qos: .userInteractive)

    private var startedAt: TimeInterval = CACurrentMediaTime()
    private var collectedReps: [RepCompleted] = []
    private var timerCancellable: AnyCancellable?
    private var realtimeStateObservation: AnyCancellable?
    private var realtimeErrorObservation: AnyCancellable?
    private var finishTask: Task<Void, Never>? = nil
    private var isFinishing = false

    /// Continuous frames in which we've seen a confident full-body pose.
    private var stableFrameCount: Int = 0
    /// Number of frames required before transitioning waiting → ready.
    private let framesForReady: Int = 18  // ~1.5s at ~12fps Vision throughput
    private var lastCameraObservationSentAt: TimeInterval = 0
    private let cameraObservationInterval: TimeInterval = 1.0
    private var latestVisualCaptureSentAt: Int = 0
    /// Hype mode keeps the energy up on a cadence instead of waiting for
    /// rep/form events (there is no form feedback to trigger speech).
    private var lastHypeCueAt: TimeInterval = 0
    private let hypeCueInterval: TimeInterval = 20.0

    init(exercise: ExerciseId, targetReps: Int, athleteName: String?,
         mode: CoachMode, shouldRecordSession: Bool) {
        self.exercise = exercise
        self.targetReps = targetReps
        self.mode = mode
        self.shouldRecordSession = shouldRecordSession
        self.analyzer = AnalyzerFactory.make(for: exercise)
        // Hype sessions are open-ended: no rep target, motivation-only prompt.
        self.realtime = RealtimeClient(exercise: exercise,
                                       targetReps: mode == .hype ? nil : targetReps,
                                       athleteName: athleteName,
                                       mode: mode)
        super.init()
        camera.delegate = self
    }

    func start() {
        camera.start()

        if shouldRecordSession {
            Task { await sessionRecorder.start() }
        }
        Task { await realtime.connect() }

        // Timer ticks all the time but only displays elapsed once active.
        timerCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.stage == .active {
                    self.elapsedMs = Int((CACurrentMediaTime() - self.startedAt) * 1000)
                    if self.mode == .hype,
                       CACurrentMediaTime() - self.lastHypeCueAt >= self.hypeCueInterval {
                        self.lastHypeCueAt = CACurrentMediaTime()
                        self.realtime.requestSpeech(reason: "keep_the_energy_up")
                    }
                }
            }

        realtimeErrorObservation = realtime.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.coachError = $0 }
    }

    func tearDown() {
        finishTask?.cancel()
        timerCancellable?.cancel()
        realtimeStateObservation?.cancel()
        realtimeErrorObservation?.cancel()
        camera.stop()
        realtime.close()
        if sessionRecorder.state.isActive {
            Task { _ = await sessionRecorder.stop() }
        }
    }

    // MARK: - User actions

    func endSet() {
        finishSet(includeTargetCueDelay: false)
    }

    /// Flip between the front (selfie) and back camera mid-session. The pose
    /// pipeline and coach connection are unaffected — only the feed changes.
    func flipCamera() {
        usingBackCamera.toggle()
        camera.setPosition(usingBackCamera ? .back : .front)
    }

    /// Called by the view when the analyzer detects rep ≥ target.
    private func handleTargetReached() {
        guard !isFinishing, !didFinish else { return }
        realtime.requestSpeech(reason: "set_target_reached")
        finishSet(includeTargetCueDelay: true)
    }

    private func finishSet(includeTargetCueDelay: Bool) {
        guard !isFinishing, !didFinish else { return }
        isFinishing = true
        stage = .finished

        finishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if includeTargetCueDelay {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
            }

            self.emitSummary()

            if self.shouldRecordSession {
                // Give the final coach cue a short tail so the saved replay
                // includes the two-way audio around set completion.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let result = await self.sessionRecorder.stop() {
                    self.recordingURL = result.url
                    self.recordingPhotoSaveState = result.photoSaveState
                }
            }

            self.didFinish = true
        }
    }

    private func emitSummary() {
        let durationMs = elapsedMs > 0 ? elapsedMs : (stage == .active ? Int((CACurrentMediaTime() - startedAt) * 1000) : 0)
        let stats = analyzer.setStats()
        realtime.sendEvent(.setFinished(
            exercise: exercise,
            reps: stats.reps,
            avgScore: stats.avgScore,
            durationMs: durationMs,
            topIssues: stats.topIssues
        ), requestSpeech: true)
        // didFinish is already true; the view observes it and navigates.
    }

    // MARK: - Pose pipeline

    nonisolated func cameraSession(_ session: CameraSession,
                                   didCapture pixelBuffer: CVPixelBuffer,
                                   at time: TimeInterval) {
        // Detection runs on the camera queue (background). Hop to main only
        // for state mutation, so we don't block frame delivery.
        let detector = self.detector
        let pose = detector.detect(in: pixelBuffer, timestamp: time)
        let visualFrameSampler = self.visualFrameSampler
        visualFrameSampler.captureIfDue(pixelBuffer: pixelBuffer, at: time) { jpegData, capturedAt in
            Task { @MainActor [weak self] in
                self?.describeVisualFrame(jpegData, capturedAt: capturedAt)
            }
        }

        Task { @MainActor [weak self] in
            self?.ingest(pose: pose)
        }
    }

    /// Called on the main actor for every camera frame, with `pose == nil` when
    /// no body is detected. The stage machine + analyzer live here.
    private func ingest(pose: Pose?) {
        // Stage machine: hold off the waiting → ready transition until the
        // *whole body* has been stably in frame, so the coach's greeting can
        // honestly say it sees the athlete fully framed.
        let fullBodyVisible = pose.map(isFullBodyVisible) ?? false
        if fullBodyVisible {
            stableFrameCount += 1
        } else {
            stableFrameCount = max(0, stableFrameCount - 2) // decay faster on misses
        }

        if stage == .waiting, stableFrameCount >= framesForReady {
            stage = .ready
            // Tell the coach to greet so the athlete (with headphones on) hears it.
            realtime.sendEvent(.setReady(exercise: exercise,
                                         targetReps: mode == .hype ? nil : targetReps,
                                         framing: pose.map { framingLabel(for: $0) } ?? "well_framed",
                                         fullBodyVisible: true),
                               requestSpeech: true)
            // Hype sessions don't wait for a first counted rep — the clock and
            // the motivation start as soon as the athlete is in frame.
            if mode == .hype {
                stage = .active
                startedAt = CACurrentMediaTime()
                lastHypeCueAt = CACurrentMediaTime()
                realtime.sendEvent(.setStarted(exercise: exercise, targetReps: nil),
                                   requestSpeech: false)
            }
        }

        guard let pose = pose else {
            maybeSendCameraObservation(pose: nil)
            return
        }

        let events = analyzer.update(pose)
        snapshot = analyzer.snapshot()
        maybeSendCameraObservation(pose: pose)

        for ev in events {
            switch ev {
            case .repCompleted(let rep):
                // First rep transitions ready → active and starts the timer.
                if stage != .active {
                    stage = .active
                    startedAt = CACurrentMediaTime() - Double(rep.durationMs) / 1000
                    realtime.sendEvent(.setStarted(exercise: exercise, targetReps: targetReps),
                                       requestSpeech: false)
                }
                collectedReps.append(rep)
                let shouldSpeak = mode == .hype
                    ? rep.index % 5 == 0
                    : rep.index == targetReps || rep.issues.contains { $0.severity == .severe }
                realtime.sendEvent(.repCompleted(rep), requestSpeech: shouldSpeak)
                if mode == .form, rep.index >= targetReps {
                    handleTargetReached()
                }
            case .formIssue(let issue, let exercise):
                // Only react to form issues once a set is actually live — and
                // never in hype mode, which promises zero form critique.
                guard stage == .active, mode == .form else { continue }
                realtime.sendEvent(.formIssue(exercise: exercise,
                                              issue: issue.id,
                                              severity: issue.severity),
                                   requestSpeech: issue.severity == .severe)
            case .phaseChanged:
                break
            }
        }
    }

    // MARK: - Demo helpers (for when the camera can't see the user)

    func manualRep() {
        let index = snapshot.reps + 1
        let rep = RepCompleted(exercise: exercise, index: index,
                               durationMs: 1500, score: 0.9, issues: [])
        if stage != .active {
            stage = .active
            startedAt = CACurrentMediaTime() - Double(rep.durationMs) / 1000
            realtime.sendEvent(.setStarted(exercise: exercise, targetReps: targetReps),
                               requestSpeech: false)
        }
        collectedReps.append(rep)
        snapshot.reps = index
        snapshot.lastScore = rep.score
        realtime.sendEvent(.repCompleted(rep), requestSpeech: index == targetReps)
        if index >= targetReps { handleTargetReached() }
    }

    func manualIssue() {
        let issue: FormIssueId
        switch exercise {
        case .squat:  issue = .squatShallowDepth
        case .pushup: issue = .pushupPartialRom
        case .pullup: issue = .pullupChinShort
        }
        realtime.sendEvent(.formIssue(exercise: exercise, issue: issue, severity: .moderate),
                           requestSpeech: true)
    }

    var collectedRepsSnapshot: [RepCompleted] { collectedReps }

    private func maybeSendCameraObservation(pose: Pose?) {
        let now = CACurrentMediaTime()
        guard now - lastCameraObservationSentAt >= cameraObservationInterval else { return }
        lastCameraObservationSentAt = now

        let observation = buildCameraObservation(pose: pose)
        realtime.sendEvent(.cameraObservation(observation),
                           requestSpeech: false,
                           queueIfDisconnected: false)
    }

    private func buildCameraObservation(pose: Pose?) -> CameraObservation {
        guard let pose else {
            return CameraObservation(
                exercise: exercise,
                workoutStage: String(describing: stage),
                targetReps: targetReps,
                reps: snapshot.reps,
                phase: snapshot.phase,
                activeIssues: snapshot.activeIssues,
                poseVisible: false,
                fullBodyVisible: false,
                framing: "no_body_pose_detected",
                bodyBox: nil,
                avgConfidence: nil,
                visibleKeypoints: [],
                keypoints: []
            )
        }

        let landmarks = poseLandmarks(from: pose)
        let box = bodyBox(from: landmarks)
        let avgConfidence = landmarks.isEmpty
            ? nil
            : rounded(landmarks.map(\.confidence).reduce(0, +) / Double(landmarks.count))
        let fullBodyVisible = isFullBodyVisible(pose)

        return CameraObservation(
            exercise: exercise,
            workoutStage: String(describing: stage),
            targetReps: targetReps,
            reps: snapshot.reps,
            phase: snapshot.phase,
            activeIssues: snapshot.activeIssues,
            poseVisible: true,
            fullBodyVisible: fullBodyVisible,
            framing: framingLabel(bodyBox: box, fullBodyVisible: fullBodyVisible),
            bodyBox: box,
            avgConfidence: avgConfidence,
            visibleKeypoints: landmarks.map(\.name),
            keypoints: landmarks
        )
    }

    /// Keypoints that must all be present for the athlete to count as "fully
    /// in frame" — shoulders down to ankles.
    private static let fullBodyKeypoints: [KeypointName] = [
        .leftShoulder, .rightShoulder, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]

    private func isFullBodyVisible(_ pose: Pose) -> Bool {
        WorkoutController.fullBodyKeypoints.allSatisfy { pose.keypoints[$0] != nil }
    }

    private func poseLandmarks(from pose: Pose) -> [PoseLandmark] {
        pose.keypoints.values
            .sorted { $0.name.rawValue < $1.name.rawValue }
            .map {
                PoseLandmark(name: $0.name.rawValue,
                             x: rounded(Double($0.x)),
                             y: rounded(Double($0.y)),
                             confidence: rounded($0.score))
            }
    }

    private func bodyBox(from landmarks: [PoseLandmark]) -> BodyBox {
        let xs = landmarks.map(\.x)
        let ys = landmarks.map(\.y)
        return BodyBox(minX: rounded(xs.min() ?? 0),
                       minY: rounded(ys.min() ?? 0),
                       maxX: rounded(xs.max() ?? 0),
                       maxY: rounded(ys.max() ?? 0))
    }

    /// Framing label for a pose, computed end-to-end from its keypoints.
    private func framingLabel(for pose: Pose) -> String {
        let box = bodyBox(from: poseLandmarks(from: pose))
        return framingLabel(bodyBox: box, fullBodyVisible: isFullBodyVisible(pose))
    }

    private func framingLabel(bodyBox: BodyBox, fullBodyVisible: Bool) -> String {
        if !fullBodyVisible { return "partial_body_visible" }
        let width = bodyBox.maxX - bodyBox.minX
        let height = bodyBox.maxY - bodyBox.minY
        if bodyBox.minX < 0.04 || bodyBox.maxX > 0.96 || bodyBox.minY < 0.04 || bodyBox.maxY > 0.96 {
            return "near_edge_of_frame"
        }
        if width < 0.18 || height < 0.35 { return "too_far_from_camera" }
        if width > 0.85 || height > 0.90 { return "too_close_to_camera" }
        return "well_framed"
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func describeVisualFrame(_ jpegData: Data, capturedAt: Int) {
        guard stage != .finished else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await BackendClient.describeFrame(
                    exercise: self.exercise,
                    jpegData: jpegData,
                    capturedAt: capturedAt
                )
                guard result.capturedAt >= self.latestVisualCaptureSentAt else { return }
                self.latestVisualCaptureSentAt = result.capturedAt

                let observation = VisualObservation(
                    exercise: self.exercise,
                    workoutStage: String(describing: self.stage),
                    reps: self.snapshot.reps,
                    description: result.description,
                    facts: result.facts,
                    model: result.model,
                    capturedAt: result.capturedAt,
                    analyzedAt: result.analyzedAt,
                    receivedAt: Int(Date().timeIntervalSince1970 * 1000)
                )
                self.realtime.sendEvent(.visualObservation(observation),
                                        requestSpeech: false,
                                        queueIfDisconnected: true)
            } catch {
                print("[vision] describe frame failed: \(error.localizedDescription)")
            }
        }
    }
}

struct WorkoutView: View {
    @EnvironmentObject var session: SessionState

    var body: some View {
        WorkoutSession(exercise: session.exercise,
                       targetReps: session.targetReps,
                       athleteName: session.athleteName,
                       mode: session.mode,
                       shouldRecordSession: session.recordSession)
    }
}

private struct WorkoutSession: View {
    @EnvironmentObject var session: SessionState
    @StateObject private var controller: WorkoutController
    @State private var permissionDenied = false
    private let mode: CoachMode

    init(exercise: ExerciseId, targetReps: Int, athleteName: String,
         mode: CoachMode, shouldRecordSession: Bool) {
        self.mode = mode
        _controller = StateObject(wrappedValue: WorkoutController(
            exercise: exercise,
            targetReps: targetReps,
            athleteName: athleteName,
            mode: mode,
            shouldRecordSession: shouldRecordSession))
    }

    var body: some View {
        ZStack {
            CameraPreviewView(session: controller.camera.session)
                .ignoresSafeArea()
                .background(Color.black)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                hud
                if let err = controller.coachError {
                    errorBanner(err)
                }
                if case .failed(let message) = controller.sessionRecorder.state {
                    errorBanner("Recording: \(message)")
                }
                if mode == .form, !controller.snapshot.activeIssues.isEmpty {
                    issueBanner
                }
                Spacer()
                if controller.stage != .active && controller.stage != .finished {
                    stageOverlay
                }
                bottomBar
            }
            .padding(Spacing.md)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            // Configure camera + permissions once when the view appears.
            let granted = await CameraSession.requestPermission()
            if !granted {
                permissionDenied = true
                return
            }
            // Reconfigure controller now that we know the exercise/target.
            // (StateObject already exists; we just kick start with current values.)
            controller.start()
        }
        .onDisappear { controller.tearDown() }
        .onChange(of: controller.didFinish) { finished in
            if finished {
                let durationMs = Int(controller.elapsedMs)
                let summary = SetSummary.build(
                    exercise: session.exercise,
                    reps: controller.collectedRepsSnapshot,
                    durationMs: durationMs,
                    recordingURL: controller.recordingURL,
                    recordingPhotoSaveState: controller.recordingPhotoSaveState,
                    mode: mode)
                session.summary = summary
                session.goSummary()
            }
        }
        .alert("Camera access needed",
               isPresented: $permissionDenied,
               actions: {
                Button("OK") { session.popToHome() }
               },
               message: { Text("Spottr can't analyze your form without the camera. You can grant access in Settings.") })
    }

    // MARK: - Actions

    /// End-set handler that always navigates, even if the realtime client is
    /// in an error state. Builds the summary inline from whatever reps the
    /// controller has collected, then pushes the Summary screen.
    private func finishNow() {
        controller.endSet()
    }

    // MARK: - Subviews

    private var stageOverlay: some View {
        let isReady = controller.stage == .ready
        let title = isReady ? "Ready when you are" : "Looking for you…"
        let readySubtitle = mode == .hype
            ? "Get moving — your coach brings the energy from here."
            : "Start your first \(session.exercise.displayName.lowercased()) — Spottr will count from there."
        let subtitle = isReady
            ? readySubtitle
            : "Step fully into the frame so the camera can see your whole body."
        let icon = isReady ? "figure.strengthtraining.traditional" : "figure.stand"

        return VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(isReady ? Theme.accent : Theme.textDim)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md + 4)
        .background(Color.black.opacity(0.78))
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(isReady ? Theme.accent : Theme.border, lineWidth: 1)
        )
    }

    private var hud: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if mode == .hype {
                    // No rep target and no form scoring in a motivation session.
                    stat("TIME", formatTime(ms: controller.elapsedMs), accent: true)
                } else {
                    stat("REPS", "\(controller.snapshot.reps)/\(session.targetReps)", accent: true)
                    stat("TIME", formatTime(ms: controller.elapsedMs))
                    stat("SCORE", controller.snapshot.lastScore.map { "\(Int($0 * 100))" } ?? "—")
                }
            }
            cueBox
            if controller.sessionRecorder.state.isActive || controller.recordingURL != nil {
                recordingBanner
            }
        }
    }

    private var recordingBanner: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Theme.bad)
                .frame(width: 8, height: 8)
            Text(recordingLabel(controller.sessionRecorder.state))
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundColor(Theme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 2)
        .background(Color.black.opacity(0.78))
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Theme.bad.opacity(0.8), lineWidth: 1)
        )
    }

    private var cueBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(connectionLabel(controller.realtime.state).uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(Theme.accent)
            Text(controller.realtime.currentCue.isEmpty
                 ? (controller.realtime.state == .connected ? "Listening…" : "—")
                 : controller.realtime.currentCue)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(2)
                .frame(minHeight: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.black.opacity(0.78))
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func stat(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .medium)).tracking(1).foregroundColor(Theme.textDim)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(accent ? Theme.accent : Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm + 2)
        .background(Color.black.opacity(0.7))
        .cornerRadius(Radius.md)
    }

    private func errorBanner(_ msg: String) -> some View {
        Text("Coach error: \(msg)")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(Spacing.sm + 2)
            .background(Theme.bad.opacity(0.9))
            .cornerRadius(Radius.md)
    }

    private var issueBanner: some View {
        VStack(spacing: 4) {
            ForEach(controller.snapshot.activeIssues.prefix(2), id: \.self) { id in
                Text(id.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm + 2)
        .background(Theme.bad.opacity(0.85))
        .cornerRadius(Radius.md)
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                if mode == .form {
                    manualDemoButtons
                }
                Spacer(minLength: 0)
                if CameraSession.hasCamera(at: .back) {
                    flipCameraButton
                }
            }
            Button(action: finishNow) {
                Text(mode == .hype ? "End session" : "End set")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(Theme.bad)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Demo-only controls for when the camera can't see the athlete. Form
    /// sessions only — hype mode has no rep target or form issues to fake.
    private var manualDemoButtons: some View {
        HStack(spacing: Spacing.md) {
            Button(action: { controller.manualRep() }) {
                Text("+ Rep")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.004, green: 0.125, blue: 0.094))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm + 4)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            Button(action: { controller.manualIssue() }) {
                Text("Issue")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.122, green: 0.075, blue: 0.0))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm + 4)
                    .background(Theme.warn)
                    .clipShape(Capsule())
            }
        }
    }

    /// Circular control that flips between the front and back camera.
    private var flipCameraButton: some View {
        Button(action: { controller.flipCamera() }) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(controller.usingBackCamera ? Theme.accent : Theme.text)
                .frame(width: 46, height: 46)
                .background(Color.black.opacity(0.72))
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        controller.usingBackCamera ? Theme.accent : Theme.border, lineWidth: 1)
                )
        }
        .accessibilityLabel(controller.usingBackCamera
                            ? "Switch to front camera"
                            : "Switch to back camera")
    }

    private func formatTime(ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func connectionLabel(_ s: RealtimeState) -> String {
        switch s {
        case .idle: return "Idle"
        case .fetchingSession: return "Connecting to coach…"
        case .connecting: return "Connecting…"
        case .connected: return "Coach"
        case .speaking: return "Coach speaking"
        case .error: return "Coach offline"
        case .closed: return "Coach disconnected"
        }
    }

    private func recordingLabel(_ state: SessionRecordingState) -> String {
        switch state {
        case .idle:
            return "Recording ready"
        case .starting:
            return "Starting recording"
        case .recording:
            return "Recording"
        case .stopping:
            return "Saving recording"
        case .saved:
            return "Recording saved"
        case .failed:
            return "Recording failed"
        }
    }
}
