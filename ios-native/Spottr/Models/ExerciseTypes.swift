import Foundation

enum ExerciseId: String, Codable, CaseIterable, Hashable {
    case squat
    case pushup
    case pullup

    var displayName: String {
        switch self {
        case .squat:  return "Squat"
        case .pushup: return "Push-up"
        case .pullup: return "Pull-up"
        }
    }
}

enum FormIssueId: String, Codable, Hashable {
    case squatShallowDepth   = "squat_shallow_depth"
    case squatKneeValgus     = "squat_knee_valgus"
    case squatForwardLean    = "squat_forward_lean"
    case squatFastDescent    = "squat_fast_descent"
    case pushupHipSag        = "pushup_hip_sag"
    case pushupPartialRom    = "pushup_partial_rom"
    case pushupElbowFlare    = "pushup_elbow_flare"
    case pushupFastRep       = "pushup_fast_rep"
    case pullupChinShort     = "pullup_chin_short"
    case pullupNoLockout     = "pullup_no_lockout"
    case pullupKipping       = "pullup_kipping"

    var label: String {
        switch self {
        case .squatShallowDepth: return "Insufficient depth"
        case .squatKneeValgus:   return "Knees caving in"
        case .squatForwardLean:  return "Excessive forward lean"
        case .squatFastDescent:  return "Descending too fast"
        case .pushupHipSag:      return "Hips sagging"
        case .pushupPartialRom:  return "Partial range of motion"
        case .pushupElbowFlare:  return "Elbows flaring out"
        case .pushupFastRep:     return "Reps too fast"
        case .pullupChinShort:   return "Chin not over the bar"
        case .pullupNoLockout:   return "Arms not fully extended"
        case .pullupKipping:     return "Excessive body swing"
        }
    }

    var coachHint: String {
        switch self {
        case .squatShallowDepth: return "Sit deeper into the next rep."
        case .squatKneeValgus:   return "Push your knees out, in line with your toes."
        case .squatForwardLean:  return "Chest up, weight in your heels."
        case .squatFastDescent:  return "Slow the descent — about 2 seconds down."
        case .pushupHipSag:      return "Squeeze your glutes and brace your core."
        case .pushupPartialRom:  return "Lower until your chest is near the floor."
        case .pushupElbowFlare:  return "Tuck your elbows closer to your ribs."
        case .pushupFastRep:     return "Slow it down for more control."
        case .pullupChinShort:   return "Pull until your chin clears the bar."
        case .pullupNoLockout:   return "Fully extend your arms at the bottom."
        case .pullupKipping:     return "Brace your core — minimize the swing."
        }
    }
}

enum IssueSeverity: String, Codable {
    case minor, moderate, severe
}

struct FormIssue: Codable, Hashable {
    let id: FormIssueId
    let severity: IssueSeverity
}

enum RepPhase: String, Codable {
    case top
    case descending
    case bottom
    case ascending
}

struct RepCompleted: Codable, Hashable {
    let exercise: ExerciseId
    let index: Int
    let durationMs: Int
    let score: Double
    let issues: [FormIssue]
}

struct AnalyzerSnapshot {
    var phase: RepPhase = .top
    var reps: Int = 0
    var lastScore: Double? = nil
    var activeIssues: [FormIssueId] = []
}

enum AnalyzerEvent {
    case repCompleted(RepCompleted)
    case formIssue(FormIssue, exercise: ExerciseId)
    case phaseChanged(RepPhase)
}
