import CoreImage
import CoreVideo
import Foundation
import UIKit

/// Produces small JPEG snapshots from the camera stream without blocking pose
/// detection. The snapshots are for semantic vision, not archival quality.
final class VisualFrameSampler {
    private let queue = DispatchQueue(label: "com.spottr.vision.snapshot", qos: .utility)
    private let lock = NSLock()
    private let context = CIContext()
    private let interval: TimeInterval
    private var lastStartedAt: TimeInterval = 0
    private var inFlight = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func captureIfDue(pixelBuffer: CVPixelBuffer,
                      at time: TimeInterval,
                      completion: @escaping (Data, Int) -> Void) {
        lock.lock()
        let due = !inFlight && time - lastStartedAt >= interval
        if due {
            inFlight = true
            lastStartedAt = time
        }
        lock.unlock()

        guard due else { return }

        let capturedAt = Int(Date().timeIntervalSince1970 * 1000)
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.inFlight = false
                self.lock.unlock()
            }

            guard let data = self.jpegData(from: pixelBuffer) else { return }
            completion(data, capturedAt)
        }
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(.right)
            .transformed(toFitMaxDimension: 960)

        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.72)
    }
}

private extension CIImage {
    func transformed(toFitMaxDimension maxDimension: CGFloat = 960) -> CIImage {
        let width = extent.width
        let height = extent.height
        let largest = max(width, height)
        guard largest > maxDimension else { return self }

        let scale = maxDimension / largest
        return transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
