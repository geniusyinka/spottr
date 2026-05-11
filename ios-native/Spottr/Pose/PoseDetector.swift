import CoreVideo
import Foundation
import Vision

/// Wraps `VNDetectHumanBodyPoseRequest` and emits our normalized `Pose`.
///
/// Coordinate normalization: Vision returns points with origin at the **bottom-left**
/// of the image (y grows upward). Our analyzers expect **top-left** origin
/// (y grows downward, like image space). We flip y on the way out.
final class PoseDetector {

    private let request: VNDetectHumanBodyPoseRequest = {
        let r = VNDetectHumanBodyPoseRequest()
        return r
    }()

    /// Returns nil when no body pose is detected with usable confidence.
    func detect(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> Pose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNHumanBodyPoseObservation else {
            return nil
        }

        guard let recognized = try? observation.recognizedPoints(.all) else {
            return nil
        }

        var keypoints: [KeypointName: Keypoint] = [:]
        for (visionName, our) in PoseDetector.mapping {
            guard let p = recognized[visionName] else { continue }
            // Skip points the model is not confident about.
            guard p.confidence >= 0.10 else { continue }
            // Vision: y grows up. Image space we want: y grows down.
            keypoints[our] = Keypoint(name: our,
                                      x: p.location.x,
                                      y: 1.0 - p.location.y,
                                      score: Double(p.confidence))
        }
        if keypoints.isEmpty { return nil }
        return Pose(keypoints: keypoints, timestamp: timestamp)
    }

    private static let mapping: [VNHumanBodyPoseObservation.JointName: KeypointName] = [
        .nose:           .nose,
        .leftEye:        .leftEye,
        .rightEye:       .rightEye,
        .leftEar:        .leftEar,
        .rightEar:       .rightEar,
        .leftShoulder:   .leftShoulder,
        .rightShoulder:  .rightShoulder,
        .leftElbow:      .leftElbow,
        .rightElbow:     .rightElbow,
        .leftWrist:      .leftWrist,
        .rightWrist:     .rightWrist,
        .leftHip:        .leftHip,
        .rightHip:       .rightHip,
        .leftKnee:       .leftKnee,
        .rightKnee:      .rightKnee,
        .leftAnkle:      .leftAnkle,
        .rightAnkle:     .rightAnkle,
    ]
}
