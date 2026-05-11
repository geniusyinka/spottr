import AVFoundation
import CoreMedia
import UIKit

protocol CameraSessionDelegate: AnyObject {
    /// Called on the camera serial queue with each frame's pixel buffer.
    func cameraSession(_ session: CameraSession, didCapture pixelBuffer: CVPixelBuffer, at time: TimeInterval)
}

/// Front-camera AVCaptureSession that streams pixel buffers for Vision pose.
final class CameraSession: NSObject {
    let session = AVCaptureSession()
    weak var delegate: CameraSessionDelegate?

    private let videoQueue = DispatchQueue(label: "com.spottr.camera.video", qos: .userInteractive)
    private var output: AVCaptureVideoDataOutput?
    private var configured = false

    func configure() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        out.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(out) {
            session.addOutput(out)
            if let conn = out.connection(with: .video) {
                conn.videoOrientation = .portrait
                conn.isVideoMirrored = true
            }
        }
        output = out
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
