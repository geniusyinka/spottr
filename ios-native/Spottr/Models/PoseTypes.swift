import CoreGraphics
import Foundation

enum KeypointName: String, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

struct Keypoint {
    let name: KeypointName
    /// Normalized image-space coordinates. `x` and `y` are 0..1; (0,0) is top-left.
    let x: CGFloat
    let y: CGFloat
    /// Detection confidence 0..1.
    let score: Double
}

struct Pose {
    let keypoints: [KeypointName: Keypoint]
    /// CACurrentMediaTime() at the moment the frame was captured (seconds).
    let timestamp: TimeInterval
}
