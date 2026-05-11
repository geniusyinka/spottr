import Foundation

protocol ExerciseAnalyzer: AnyObject {
    var id: ExerciseId { get }
    func update(_ pose: Pose) -> [AnalyzerEvent]
    func snapshot() -> AnalyzerSnapshot
    func setStats() -> SetStats
    func reset()
}

struct SetStats {
    let reps: Int
    let avgScore: Double
    let topIssues: [FormIssueId]
}

enum AnalyzerFactory {
    static func make(for id: ExerciseId) -> ExerciseAnalyzer {
        switch id {
        case .squat:  return SquatAnalyzer()
        case .pushup: return PushupAnalyzer()
        case .pullup: return PullupAnalyzer()
        }
    }
}
