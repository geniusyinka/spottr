import AVFoundation
import CoreMedia
import UIKit

protocol CameraSessionDelegate: AnyObject {
    /// Called on the camera serial queue with each frame's pixel buffer.
    func cameraSession(_ session: CameraSession, didCapture pixelBuffer: CVPixelBuffer, at time: TimeInterval)
}

/// AVCaptureSession that streams pixel buffers for Vision pose. Supports both
/// the front (selfie) and back cameras — the front feed is mirrored so the
/// preview reads naturally; the back feed is left un-mirrored.
final class CameraSession: NSObject {
    let session = AVCaptureSession()
    weak var delegate: CameraSessionDelegate?

    /// Which physical camera is currently feeding frames.
    private(set) var position: AVCaptureDevice.Position = .front

    private let videoQueue = DispatchQueue(label: "com.spottr.camera.video", qos: .userInteractive)
    private var output: AVCaptureVideoDataOutput?
    private var currentInput: AVCaptureDeviceInput?
    private var configured = false

    func configure() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        addInput(for: position)

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        out.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(out) {
            session.addOutput(out)
        }
        output = out
        applyConnectionSettings()
        session.commitConfiguration()
        configured = true
    }

    func start() {
        configure()
        guard !session.isRunning else { return }
        videoQueue.async { [weak self] in self?.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        videoQueue.async { [weak self] in self?.session.stopRunning() }
    }

    /// Whether the device actually has a camera at the given position.
    static func hasCamera(at position: AVCaptureDevice.Position) -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) != nil
    }

    /// Flip between the front and back camera. Safe to call while running.
    func switchCamera() {
        setPosition(position == .front ? .back : .front)
    }

    /// Reconfigure the session to use the camera at `newPosition`. No-op if the
    /// device has no camera there or it's already selected.
    func setPosition(_ newPosition: AVCaptureDevice.Position) {
        guard configured, newPosition != position else { return }
        guard cameraDevice(for: newPosition) != nil else { return }

        videoQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let current = self.currentInput {
                self.session.removeInput(current)
            }
            if self.addInput(for: newPosition) {
                self.position = newPosition
            } else {
                // Couldn't add the new camera — restore the one we had.
                self.addInput(for: self.position)
            }
            self.applyConnectionSettings()
            self.session.commitConfiguration()
        }
    }

    // MARK: - Configuration helpers

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    @discardableResult
    private func addInput(for position: AVCaptureDevice.Position) -> Bool {
        guard let device = cameraDevice(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        currentInput = input
        return true
    }

    /// Keep the data-output connection portrait, and mirror only the front feed
    /// so pose coordinates and snapshots match what the user sees on screen.
    private func applyConnectionSettings() {
        guard let conn = output?.connection(with: .video) else { return }
        if conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = (position == .front)
        }
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    static func currentPermission() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts = CACurrentMediaTime()
        delegate?.cameraSession(self, didCapture: pb, at: ts)
    }
}
