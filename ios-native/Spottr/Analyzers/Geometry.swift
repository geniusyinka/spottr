import CoreGraphics
import Foundation

enum Geometry {
    /// Angle ABC in degrees (joint at B). Returns NaN if any point is missing.
    static func angle(_ a: Keypoint?, _ b: Keypoint?, _ c: Keypoint?) -> Double {
        guard let a = a, let b = b, let c = c else { return .nan }
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let m1 = (v1.dx * v1.dx + v1.dy * v1.dy).squareRoot()
        let m2 = (v2.dx * v2.dx + v2.dy * v2.dy).squareRoot()
        guard m1 > 0, m2 > 0 else { return .nan }
        let cos = max(-1.0, min(1.0, Double(dot / (m1 * m2))))
        return acos(cos) * 180.0 / .pi
    }

    static func midpoint(_ a: Keypoint?, _ b: Keypoint?) -> CGPoint? {
        guard let a = a, let b = b else { return nil }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    static func avgScore(_ kps: Keypoint?...) -> Double {
        let valid = kps.compactMap { $0 }
        guard !valid.isEmpty else { return .nan }
        return valid.map(\.score).reduce(0, +) / Double(valid.count)
    }

    static func avgFinite(_ xs: Double...) -> Double {
        let ok = xs.filter { $0.isFinite }
        guard !ok.isEmpty else { return .nan }
        return ok.reduce(0, +) / Double(ok.count)
    }

    static func scoreFromIssues(_ issues: [FormIssue]) -> Double {
        var score = 1.0
        for i in issues {
            switch i.severity {
            case .severe:   score -= 0.35
            case .moderate: score -= 0.20
            case .minor:    score -= 0.08
            }
        }
        return max(0, min(1, score))
    }
}
