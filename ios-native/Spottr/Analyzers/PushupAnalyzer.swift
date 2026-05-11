import Foundation
import QuartzCore

/// Push-up rep counter + form-issue detector.
final class PushupAnalyzer: ExerciseAnalyzer {
    let id: ExerciseId = .pushup

    private let topElbowAngle: Double = 160
    private let bottomElbowAngle: Double = 95
    private let partialElbowAngle: Double = 115
    private let fastRepMs: Int = 800
    private let issueCooldownMs: Int = 4000

    private struct Pending {
        let startedAt: TimeInterval
        var bottomAt: TimeInterval?
        var minElbowAngle: Double
        var maxHipDropRatio: Double
        var maxElbowFlare: Double
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
        let ls = kp[.leftShoulder], rs = kp[.rightShoulder]
        let le = kp[.leftElbow],    re = kp[.rightElbow]
        let lw = kp[.leftWrist],    rw = kp[.rightWrist]
        let lh = kp[.leftHip],      rh = kp[.rightHip]
        let la = kp[.leftAnkle],    ra = kp[.rightAnkle]

        let upperScore = Geometry.avgScore(ls, rs, le, re, lw, rw)
        let lineScore = Geometry.avgScore(ls, rs, lh, rh, la, ra)
        if !upperScore.isFinite || !lineScore.isFinite || upperScore < 0.35 || lineScore < 0.3 {
            return events
        }

        let leftElbow = Geometry.angle(ls, le, lw)
        let rightElbow = Geometry.angle(rs, re, rw)
        let elbowAngle = Geometry.avgFinite(leftElbow, rightElbow)
        if !elbowAngle.isFinite { return events }

        // Hip-sag: signed distance from hipMid to line(shoulderMid -> ankleMid).
        let sM = Geometry.midpoint(ls, rs)
        let hM = Geometry.midpoint(lh, rh)
        let aM = Geometry.midpoint(la, ra)
        var hipDropRatio: Double = 0
        if let s = sM, let h = hM, let a = aM {
            let dx = Double(a.x - s.x), dy = Double(a.y - s.y)
            let len = max(0.01, (dx * dx + dy * dy).squareRoot())
            let nx = -dy / len, ny = dx / len
            let signed = (Double(h.x - s.x)) * nx + (Double(h.y - s.y)) * ny
            hipDropRatio = signed / len
        }

        var elbowFlare: Double = 0
        if let ls = ls, let rs = rs, let le = le, let re = re {
            let dx = Double(ls.x - rs.x), dy = Double(ls.y - rs.y)
            let shoulderWidth = max(0.0001, (dx * dx + dy * dy).squareRoot())
            let leftFlare = abs(Double(le.x - ls.x)) / shoulderWidth
            let rightFlare = abs(Double(re.x - rs.x)) / shoulderWidth
            elbowFlare = max(leftFlare, rightFlare)
        }

        let wasPhase = phase
        let now = pose.timestamp

        switch phase {
        case .top:
            if elbowAngle < topElbowAngle - 10 {
                phase = .descending
                pending = Pending(startedAt: now, bottomAt: nil,
                                  minElbowAngle: elbowAngle,
                                  maxHipDropRatio: hipDropRatio,
                                  maxElbowFlare: elbowFlare)
            }
        case .descending:
            if pending != nil {
                pending!.minElbowAngle = min(pending!.minElbowAngle, elbowAngle)
                pending!.maxHipDropRatio = max(pending!.maxHipDropRatio, hipDropRatio)
                pending!.maxElbowFlare = max(pending!.maxElbowFlare, elbowFlare)
            }
            if elbowAngle <= bottomElbowAngle + 5 {
                phase = .bottom
                pending?.bottomAt = now
            } else if elbowAngle > topElbowAngle - 5 {
                phase = .top
                pending = nil
            }
        case .bottom:
            if pending != nil {
                pending!.minElbowAngle = min(pending!.minElbowAngle, elbowAngle)
                pending!.maxHipDropRatio = max(pending!.maxHipDropRatio, hipDropRatio)
                pending!.maxElbowFlare = max(pending!.maxElbowFlare, elbowFlare)
            }
            if elbowAngle > bottomElbowAngle + 15 {
                phase = .ascending
            }
        case .ascending:
            if elbowAngle > topElbowAngle - 8 {
                if let rep = finalizeRep(now: now) {
                    reps += 1
                    lastScore = rep.score
                    completed.append((score: rep.score, issues: rep.issues))
                    events.append(.repCompleted(.init(
                        exercise: .pushup, index: reps,
                        durationMs: rep.durationMs, score: rep.score, issues: rep.issues
                    )))
                }
                phase = .top
                pending = nil
            }
        }

        if phase != wasPhase {
            events.append(.phaseChanged(phase))
        }

        if hipDropRatio > 0.10 {
            maybeEmit(&events, now: now,
                      issue: FormIssue(id: .pushupHipSag, severity: .moderate))
        }
        if elbowFlare > 1.3, phase != .top {
            maybeEmit(&events, now: now,
                      issue: FormIssue(id: .pushupElbowFlare, severity: .moderate))
        }

        var active = Set<FormIssueId>()
        if hipDropRatio > 0.07 { active.insert(.pushupHipSag) }
        if elbowFlare > 1.15 { active.insert(.pushupElbowFlare) }
        if phase == .bottom, elbowAngle > partialElbowAngle {
            active.insert(.pushupPartialRom)
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

        if p.minElbowAngle > partialElbowAngle {
            issues.append(.init(id: .pushupPartialRom, severity: .moderate))
        } else if p.minElbowAngle > bottomElbowAngle + 10 {
            issues.append(.init(id: .pushupPartialRom, severity: .minor))
        }

        if p.maxHipDropRatio > 0.07 {
            issues.append(.init(id: .pushupHipSag,
                                severity: p.maxHipDropRatio > 0.12 ? .moderate : .minor))
        }

        if p.maxElbowFlare > 1.4 {
            issues.append(.init(id: .pushupElbowFlare, severity: .moderate))
        } else if p.maxElbowFlare > 1.15 {
            issues.append(.init(id: .pushupElbowFlare, severity: .minor))
        }

        let totalMs = Int((now - p.startedAt) * 1000)
        if totalMs > 0, totalMs < fastRepMs {
            issues.append(.init(id: .pushupFastRep,
                                severity: totalMs < 500 ? .moderate : .minor))
        }
        return (Geometry.scoreFromIssues(issues), issues, totalMs)
    }

    private func maybeEmit(_ events: inout [AnalyzerEvent], now: TimeInterval, issue: FormIssue) {
        let last = lastEmittedAt[issue.id] ?? 0
        if (now - last) * 1000 < Double(issueCooldownMs) { return }
        lastEmittedAt[issue.id] = now
        events.append(.formIssue(issue, exercise: .pushup))
    }
}
