import Foundation
import QuartzCore

/// Squat rep counter + form-issue detector. Ported from the TS analyzer.
final class SquatAnalyzer: ExerciseAnalyzer {
    let id: ExerciseId = .squat

    // Tunables (degrees / normalized image-space units).
    private let standKneeAngle: Double = 160
    private let deepKneeAngle:  Double = 100
    private let shallowKneeAngle: Double = 130
    private let fastDescentMs: Int = 600
    private let issueCooldownMs: Int = 4000

    private struct Pending {
        let startedAt: TimeInterval
        var bottomAt: TimeInterval?
        var minKneeAngle: Double
        var maxLeanDeg: Double
        var maxValgusRatio: Double
    }

    private var phase: RepPhase = .top
    private var reps = 0
    private var lastScore: Double? = nil
    private var activeIssues = Set<FormIssueId>()
    private var lastEmittedAt: [FormIssueId: TimeInterval] = [:]
    private var pending: Pending?
    private var completed: [(score: Double, issues: [FormIssue])] = []

    func update(_ pose: Pose) -> [AnalyzerEvent] {
        var events: [AnalyzerEvent] = []
        let kp = pose.keypoints
        let lh = kp[.leftHip], rh = kp[.rightHip]
        let lk = kp[.leftKnee], rk = kp[.rightKnee]
        let la = kp[.leftAnkle], ra = kp[.rightAnkle]
        let ls = kp[.leftShoulder], rs = kp[.rightShoulder]

        let lowerScore = Geometry.avgScore(lh, rh, lk, rk, la, ra)
        if !lowerScore.isFinite || lowerScore < 0.35 { return events }

        let leftKnee = Geometry.angle(lh, lk, la)
        let rightKnee = Geometry.angle(rh, rk, ra)
        let kneeAngle = Geometry.avgFinite(leftKnee, rightKnee)
        if !kneeAngle.isFinite { return events }

        let shoulderMid = Geometry.midpoint(ls, rs)
        let hipMid = Geometry.midpoint(lh, rh)
        var leanDeg: Double = 0
        if let s = shoulderMid, let h = hipMid {
            let dx = Double(s.x - h.x)
            let dy = max(0.0001, Double(h.y - s.y))
            leanDeg = atan2(abs(dx), dy) * 180 / .pi
        }

        // Knee valgus heuristic: knees narrower than ankles, normalized by hip width.
        var valgusRatio: Double = 0
        if let lk = lk, let rk = rk, let la = la, let ra = ra, let lh = lh, let rh = rh {
            let hipWidth = max(0.0001, abs(Double(lh.x - rh.x)))
            let kneeWidth = abs(Double(lk.x - rk.x))
            let ankleWidth = abs(Double(la.x - ra.x))
            valgusRatio = max(0, (ankleWidth - kneeWidth) / hipWidth)
        }

        let wasPhase = phase
        let now = pose.timestamp

        switch phase {
        case .top:
            if kneeAngle < standKneeAngle - 10 {
                phase = .descending
                pending = Pending(startedAt: now, bottomAt: nil,
                                  minKneeAngle: kneeAngle,
                                  maxLeanDeg: leanDeg,
                                  maxValgusRatio: valgusRatio)
            }
        case .descending:
            if pending != nil {
                pending!.minKneeAngle = min(pending!.minKneeAngle, kneeAngle)
                pending!.maxLeanDeg = max(pending!.maxLeanDeg, leanDeg)
                pending!.maxValgusRatio = max(pending!.maxValgusRatio, valgusRatio)
            }
            if kneeAngle <= deepKneeAngle + 5 {
                phase = .bottom
                pending?.bottomAt = now
            } else if kneeAngle > standKneeAngle - 5 {
                phase = .top
                pending = nil
            }
        case .bottom:
            if pending != nil {
                pending!.minKneeAngle = min(pending!.minKneeAngle, kneeAngle)
                pending!.maxLeanDeg = max(pending!.maxLeanDeg, leanDeg)
                pending!.maxValgusRatio = max(pending!.maxValgusRatio, valgusRatio)
            }
            if kneeAngle > deepKneeAngle + 15 {
                phase = .ascending
            }
        case .ascending:
            if kneeAngle > standKneeAngle - 8 {
                if let rep = finalizeRep(now: now) {
                    reps += 1
                    lastScore = rep.score
                    completed.append((score: rep.score, issues: rep.issues))
                    events.append(.repCompleted(.init(
                        exercise: .squat,
                        index: reps,
                        durationMs: rep.durationMs,
                        score: rep.score,
                        issues: rep.issues
                    )))
                }
                phase = .top
                pending = nil
            }
        }

        if phase != wasPhase {
            events.append(.phaseChanged(phase))
        }

        // Live form-issue detection.
        if valgusRatio > 0.25, phase == .descending || phase == .bottom {
            maybeEmit(&events, now: now,
                      issue: FormIssue(id: .squatKneeValgus,
                                       severity: valgusRatio > 0.4 ? .severe : .moderate))
        }
        if leanDeg > 45, phase != .top {
            maybeEmit(&events, now: now,
                      issue: FormIssue(id: .squatForwardLean, severity: .moderate))
        }

        var active = Set<FormIssueId>()
        if valgusRatio > 0.2 { active.insert(.squatKneeValgus) }
        if leanDeg > 35 { active.insert(.squatForwardLean) }
        if phase == .bottom, kneeAngle > shallowKneeAngle {
            active.insert(.squatShallowDepth)
        }
        activeIssues = active

        return events
    }

    func snapshot() -> AnalyzerSnapshot {
        AnalyzerSnapshot(phase: phase, reps: reps, lastScore: lastScore, activeIssues: Array(activeIssues))
    }

    func reset() {
        phase = .top; reps = 0; lastScore = nil
        activeIssues.removeAll()
        lastEmittedAt.removeAll()
        pending = nil
        completed.removeAll()
    }

    func setStats() -> SetStats {
        guard !completed.isEmpty else { return SetStats(reps: 0, avgScore: 0, topIssues: []) }
        let avg = completed.map(\.score).reduce(0, +) / Double(completed.count)
        var counts: [FormIssueId: Int] = [:]
        for r in completed { for i in r.issues { counts[i.id, default: 0] += 1 } }
        let top = counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        return SetStats(reps: completed.count, avgScore: avg, topIssues: Array(top))
    }

    // ---- internal ----

    private func finalizeRep(now: TimeInterval) -> (score: Double, issues: [FormIssue], durationMs: Int)? {
        guard let p = pending else { return nil }
        var issues: [FormIssue] = []

        if p.minKneeAngle > shallowKneeAngle {
            issues.append(.init(id: .squatShallowDepth, severity: .moderate))
        } else if p.minKneeAngle > deepKneeAngle + 10 {
            issues.append(.init(id: .squatShallowDepth, severity: .minor))
        }

        if p.maxLeanDeg > 45 {
            issues.append(.init(id: .squatForwardLean, severity: .moderate))
        } else if p.maxLeanDeg > 35 {
            issues.append(.init(id: .squatForwardLean, severity: .minor))
        }

        if p.maxValgusRatio > 0.4 {
            issues.append(.init(id: .squatKneeValgus, severity: .severe))
        } else if p.maxValgusRatio > 0.2 {
            issues.append(.init(id: .squatKneeValgus, severity: .moderate))
        }

        let descentMs = Int(((p.bottomAt ?? now) - p.startedAt) * 1000)
        if descentMs > 0, descentMs < fastDescentMs {
            issues.append(.init(id: .squatFastDescent,
                                severity: descentMs < 350 ? .moderate : .minor))
        }

        let durationMs = Int((now - p.startedAt) * 1000)
        return (Geometry.scoreFromIssues(issues), issues, durationMs)
    }

    private func maybeEmit(_ events: inout [AnalyzerEvent], now: TimeInterval, issue: FormIssue) {
        let last = lastEmittedAt[issue.id] ?? 0
        if (now - last) * 1000 < Double(issueCooldownMs) { return }
        lastEmittedAt[issue.id] = now
        events.append(.formIssue(issue, exercise: .squat))
    }
}
