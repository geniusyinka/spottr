import CoreGraphics
import Foundation

/// Pull-up rep counter + form-issue detector.
///
/// Convention (matches the other analyzers):
///   - `top` = starting hang (arms extended) — image-space body is *low*
///   - `descending` = pulling up (elbow angle decreasing, body rising)
///   - `bottom` = chin over the bar (peak of the rep)
///   - `ascending` = lowering back to the hang
///
/// Image-space y grows downward (we flip Vision's coords on the way in), so a
/// LOWER y value means physically HIGHER in space. Chin-over-bar is detected
/// by comparing nose y to wrist y.
final class PullupAnalyzer: ExerciseAnalyzer {
    let id: ExerciseId = .pullup

    private let extendedElbowAngle: Double = 160   // arms locked out
    private let pullElbowAngle: Double = 130       // we're definitely pulling
    private let chinOverBarMargin: CGFloat = 0.02  // nose at least 2% above wrists
    private let issueCooldownMs: Int = 4000

    private struct Pending {
        let startedAt: TimeInterval
        var bottomAt: TimeInterval?
        var minElbowAngle: Double
        var minNoseY: CGFloat            // smallest (= highest) nose y of the rep
        var startWristY: CGFloat
        var maxHipSwayDelta: CGFloat
        var startHipX: CGFloat
        var startedExtended: Bool
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
        let nose = kp[.nose]
        let ls = kp[.leftShoulder], rs = kp[.rightShoulder]
        let le = kp[.leftElbow],    re = kp[.rightElbow]
        let lw = kp[.leftWrist],    rw = kp[.rightWrist]
        let lh = kp[.leftHip],      rh = kp[.rightHip]

        // Need head + arms confidently visible.
        let headScore = Geometry.avgScore(nose, ls, rs)
        let armsScore = Geometry.avgScore(le, re, lw, rw)
        if !headScore.isFinite || !armsScore.isFinite || headScore < 0.30 || armsScore < 0.30 {
            return events
        }
        guard let nose = nose else { return events }

        let leftElbow = Geometry.angle(ls, le, lw)
        let rightElbow = Geometry.angle(rs, re, rw)
        let elbowAngle = Geometry.avgFinite(leftElbow, rightElbow)
        if !elbowAngle.isFinite { return events }

        // Wrist (= bar) y. Average of left/right.
        let wristY: CGFloat = {
            if let l = lw, let r = rw { return (l.y + r.y) / 2 }
            return lw?.y ?? rw?.y ?? .nan
        }()
        let chinOverBar = wristY.isFinite && nose.y + chinOverBarMargin < wristY

        // Hip x for kipping detection (horizontal sway).
        let hipX: CGFloat = {
            if let l = lh, let r = rh { return (l.x + r.x) / 2 }
            return lh?.x ?? rh?.x ?? .nan
        }()

        let wasPhase = phase
        let now = pose.timestamp

        switch phase {
        case .top:
            // From the hang, started pulling.
            if elbowAngle < extendedElbowAngle - 10 {
                phase = .descending
                pending = Pending(
                    startedAt: now,
                    bottomAt: nil,
                    minElbowAngle: elbowAngle,
                    minNoseY: nose.y,
                    startWristY: wristY,
                    maxHipSwayDelta: 0,
                    startHipX: hipX,
                    startedExtended: elbowAngle >= extendedElbowAngle - 5
                )
            }
        case .descending:
            if pending != nil {
                pending!.minElbowAngle = min(pending!.minElbowAngle, elbowAngle)
                pending!.minNoseY = min(pending!.minNoseY, nose.y)
                if hipX.isFinite, pending!.startHipX.isFinite {
                    pending!.maxHipSwayDelta = max(pending!.maxHipSwayDelta,
                                                   abs(hipX - pending!.startHipX))
                }
            }
            // "Bottom" of our convention = top of the pull-up motion: chin over bar
            // OR elbow angle compressed enough that the user is at peak.
            if chinOverBar || elbowAngle < pullElbowAngle - 30 {
                phase = .bottom
                pending?.bottomAt = now
            } else if elbowAngle > extendedElbowAngle - 5 {
                // bailed out before any pull
                phase = .top
                pending = nil
            }
        case .bottom:
            if pending != nil {
                pending!.minElbowAngle = min(pending!.minElbowAngle, elbowAngle)
                pending!.minNoseY = min(pending!.minNoseY, nose.y)
            }
            // Started lowering: elbow opens up again.
            if elbowAngle > pullElbowAngle {
                phase = .ascending
            }
        case .ascending:
            if elbowAngle > extendedElbowAngle - 8 {
                if let rep = finalizeRep(now: now, finalWristY: wristY) {
                    reps += 1
                    lastScore = rep.score
                    completed.append((score: rep.score, issues: rep.issues))
                    events.append(.repCompleted(.init(
                        exercise: .pullup,
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

        // Live form-issue cues during the descending/bottom phase.
        if let p = pending, phase == .bottom, !chinOverBar, p.startWristY.isFinite {
            // We hit "bottom" via elbow compression but chin never cleared the bar.
            maybeEmit(&events, now: now,
                      issue: FormIssue(id: .pullupChinShort, severity: .moderate))
        }
        if let p = pending, p.maxHipSwayDelta > 0.10, phase != .top {
            maybeEmit(&events, now: now,
                      issue: FormIssue(id: .pullupKipping, severity: .moderate))
        }

        var active = Set<FormIssueId>()
        if let p = pending, !chinOverBar, phase == .bottom { active.insert(.pullupChinShort) }
        if let p = pending, p.maxHipSwayDelta > 0.07 { active.insert(.pullupKipping) }
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

    private func finalizeRep(now: TimeInterval, finalWristY: CGFloat) -> (score: Double, issues: [FormIssue], durationMs: Int)? {
        guard let p = pending else { return nil }
        var issues: [FormIssue] = []

        // Chin-over-bar: peak nose y must be at least `margin` above wrist y.
        let cleared = p.startWristY.isFinite && p.minNoseY + chinOverBarMargin < p.startWristY
        if !cleared {
            issues.append(.init(id: .pullupChinShort, severity: .moderate))
        }

        // Lockout: did the user start fully extended?
        if !p.startedExtended {
            issues.append(.init(id: .pullupNoLockout, severity: .minor))
        }

        // Kipping: large horizontal hip swing during the rep.
        if p.maxHipSwayDelta > 0.10 {
            issues.append(.init(id: .pullupKipping,
                                severity: p.maxHipSwayDelta > 0.18 ? .moderate : .minor))
        }

        let totalMs = Int((now - p.startedAt) * 1000)
        return (Geometry.scoreFromIssues(issues), issues, totalMs)
    }

    private func maybeEmit(_ events: inout [AnalyzerEvent], now: TimeInterval, issue: FormIssue) {
        let last = lastEmittedAt[issue.id] ?? 0
        if (now - last) * 1000 < Double(issueCooldownMs) { return }
        lastEmittedAt[issue.id] = now
        events.append(.formIssue(issue, exercise: .pullup))
    }
}
