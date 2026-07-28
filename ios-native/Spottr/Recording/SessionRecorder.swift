import Foundation
import Photos
import ReplayKit

enum SessionRecordingState: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case saved(URL)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .recording, .stopping:
            return true
        case .idle, .saved, .failed:
            return false
        }
    }
}

enum PhotoSaveState: Equatable {
    case notRequested
    case saving
    case saved
    case denied
    case failed(String)

    var summaryText: String {
        switch self {
        case .notRequested:
            return "Saved locally on this iPhone."
        case .saving:
            return "Saving to Photos..."
        case .saved:
            return "Saved locally and to Photos."
        case .denied:
            return "Saved locally. Photos permission was not granted."
        case .failed(let message):
            return "Saved locally. Photos save failed: \(message)"
        }
    }
}

struct SessionRecordingResult: Equatable {
    let url: URL
    let photoSaveState: PhotoSaveState
}

@MainActor
final class SessionRecorder: NSObject, ObservableObject {
    @Published private(set) var state: SessionRecordingState = .idle
    @Published private(set) var photoSaveState: PhotoSaveState = .notRequested

    private let recorder = RPScreenRecorder.shared()
    private var outputURL: URL?

    func start() async {
        guard !recorder.isRecording else {
            state = .recording
            return
        }
        guard recorder.isAvailable else {
            state = .failed("Screen recording is not available on this device right now.")
            return
        }

        do {
            let url = try makeOutputURL()
            try? FileManager.default.removeItem(at: url)
            outputURL = url
            photoSaveState = .notRequested

            recorder.delegate = self
            recorder.isMicrophoneEnabled = true
            recorder.isCameraEnabled = false
            state = .starting

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                recorder.startRecording { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: ())
                    }
                }
            }
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async -> SessionRecordingResult? {
        guard recorder.isRecording else {
            if case .saved(let url) = state {
                return SessionRecordingResult(url: url, photoSaveState: photoSaveState)
            }
            return nil
        }

        let url: URL
        do {
            url = try outputURL ?? makeOutputURL()
            try? FileManager.default.removeItem(at: url)
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }

        state = .stopping
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                recorder.stopRecording(withOutput: url) { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: ())
                    }
                }
            }
            state = .saved(url)
            let photoState = await saveToPhotos(url)
            return SessionRecordingResult(url: url, photoSaveState: photoState)
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    private func makeOutputURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Recordings", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let filename = "spottr-session-\(formatter.string(from: Date())).mp4"
        return dir.appending(path: filename)
    }

    private func saveToPhotos(_ url: URL) async -> PhotoSaveState {
        photoSaveState = .saving

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let finalStatus: PHAuthorizationStatus
        if status == .notDetermined {
            finalStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            finalStatus = status
        }

        guard finalStatus == .authorized || finalStatus == .limited else {
            photoSaveState = .denied
            return .denied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            photoSaveState = .saved
            return .saved
        } catch {
            let failed: PhotoSaveState = .failed(error.localizedDescription)
            photoSaveState = failed
            return failed
        }
    }
}

extension SessionRecorder: RPScreenRecorderDelegate {
    nonisolated func screenRecorder(_ screenRecorder: RPScreenRecorder,
                                    didStopRecordingWith previewViewController: RPPreviewViewController?,
                                    error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.state = .failed(error.localizedDescription)
        }
    }

    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {}
}
