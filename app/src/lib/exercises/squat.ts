import { angleDeg, avgScore } from './geometry';
import type {
  AnalyzerEvent,
  AnalyzerSnapshot,
  ExerciseAnalyzer,
  FormIssue,
  FormIssueId,
  Pose,
  RepPhase,
} from './types';

// Thresholds (degrees / normalized image units). Tuned for front-facing camera,
// person filling most of the frame.
const STAND_KNEE_ANGLE = 160; // ~straight
const DEEP_KNEE_ANGLE = 100; // counts as a deep squat
const SHALLOW_KNEE_ANGLE = 130; // anything above this at the bottom = shallow

const FAST_DESCENT_MS = 600; // top -> bottom faster than this = uncontrolled

const ISSUE_COOLDOWN_MS = 4000; // don't re-emit the same issue more often than this

interface PendingRep {
  startedAt: number;
  bottomAt: number | null;
  minKneeAngle: number;
  maxLeanDeg: number;
  maxValgusRatio: number; // 0 = knees aligned, larger = caving
}

export class SquatAnalyzer implements ExerciseAnalyzer {
  readonly id = 'squat' as const;

  private phase: RepPhase = 'top';
  private reps = 0;
  private lastScore: number | null = null;
  private activeIssues = new Set<FormIssueId>();
  private lastEmittedAt = new Map<FormIssueId, number>();
  private pending: PendingRep | null = null;
  private completed: { score: number; issues: FormIssue[] }[] = [];

  update(pose: Pose): AnalyzerEvent[] {
    const events: AnalyzerEvent[] = [];
    const kp = pose.keypoints;
    const ls = kp.left_shoulder;
    const rs = kp.right_shoulder;
    const lh = kp.left_hip;
    const rh = kp.right_hip;
    const lk = kp.left_knee;
    const rk = kp.right_knee;
    const la = kp.left_ankle;
    const ra = kp.right_ankle;

    // Need a confident lower-body view to analyze.
    const lowerScore = avgScore(lh, rh, lk, rk, la, ra);
    if (!isFinite(lowerScore) || lowerScore < 0.35) {
      return events;
    }

    const leftKnee = angleDeg(lh, lk, la);
    const rightKnee = angleDeg(rh, rk, ra);
    const kneeAngle = avgFinite(leftKnee, rightKnee);
    if (!isFinite(kneeAngle)) return events;

    // Forward lean: torso vector vs vertical. Bigger angle = more lean.
    const shoulderMid = mid(ls, rs);
    const hipMid = mid(lh, rh);
    let leanDeg = 0;
    if (shoulderMid && hipMid) {
      const dx = shoulderMid.x - hipMid.x;
      const dy = hipMid.y - shoulderMid.y; // image y grows downward
      leanDeg = (Math.atan2(Math.abs(dx), Math.max(0.0001, dy)) * 180) / Math.PI;
    }

    // Knee valgus heuristic: how far knees are inside the ankle line.
    // Positive ratio = caving in. Normalized by hip width.
    let valgusRatio = 0;
    if (lk && rk && la && ra && lh && rh) {
      const hipWidth = Math.max(0.0001, Math.abs(lh.x - rh.x));
      const kneeWidth = Math.abs(lk.x - rk.x);
      const ankleWidth = Math.abs(la.x - ra.x);
      // If knees narrower than ankles relative to hips, that's valgus.
      valgusRatio = Math.max(0, (ankleWidth - kneeWidth) / hipWidth);
    }

    // Phase machine.
    const wasPhase = this.phase;
    if (this.phase === 'top') {
      if (kneeAngle < STAND_KNEE_ANGLE - 10) {
        this.phase = 'descending';
        this.pending = {
          startedAt: pose.timestamp,
          bottomAt: null,
          minKneeAngle: kneeAngle,
          maxLeanDeg: leanDeg,
          maxValgusRatio: valgusRatio,
        };
      }
    } else if (this.phase === 'descending') {
      if (this.pending) {
        this.pending.minKneeAngle = Math.min(this.pending.minKneeAngle, kneeAngle);
        this.pending.maxLeanDeg = Math.max(this.pending.maxLeanDeg, leanDeg);
        this.pending.maxValgusRatio = Math.max(this.pending.maxValgusRatio, valgusRatio);
      }
      if (kneeAngle <= DEEP_KNEE_ANGLE + 5) {
        this.phase = 'bottom';
        if (this.pending) this.pending.bottomAt = pose.timestamp;
      } else if (kneeAngle > STAND_KNEE_ANGLE - 5) {
        // bailed out before reaching depth
        this.phase = 'top';
        this.pending = null;
      }
    } else if (this.phase === 'bottom') {
      if (this.pending) {
        this.pending.minKneeAngle = Math.min(this.pending.minKneeAngle, kneeAngle);
        this.pending.maxLeanDeg = Math.max(this.pending.maxLeanDeg, leanDeg);
        this.pending.maxValgusRatio = Math.max(this.pending.maxValgusRatio, valgusRatio);
      }
      if (kneeAngle > DEEP_KNEE_ANGLE + 15) {
        this.phase = 'ascending';
      }
    } else if (this.phase === 'ascending') {
      if (kneeAngle > STAND_KNEE_ANGLE - 8) {
        // Rep complete.
        const rep = this.finalizeRep(pose.timestamp);
        if (rep) {
          this.reps += 1;
          this.lastScore = rep.score;
          this.completed.push({ score: rep.score, issues: rep.issues });
          events.push({
            type: 'rep_completed',
            timestamp: pose.timestamp,
            rep: {
              exercise: 'squat',
              index: this.reps,
              durationMs: rep.durationMs,
              score: rep.score,
              issues: rep.issues,
            },
          });
        }
        this.phase = 'top';
        this.pending = null;
      }
    }

    if (this.phase !== wasPhase) {
      events.push({ type: 'phase_changed', phase: this.phase, timestamp: pose.timestamp });
    }

    // Live form-issue detection (transient cues while in motion).
    this.checkActiveIssues({
      now: pose.timestamp,
      kneeAngle,
      leanDeg,
      valgusRatio,
      events,
    });

    return events;
  }

  snapshot(): AnalyzerSnapshot {
    return {
      phase: this.phase,
      reps: this.reps,
      lastScore: this.lastScore,
      activeIssues: [...this.activeIssues],
    };
  }

  reset(): void {
    this.phase = 'top';
    this.reps = 0;
    this.lastScore = null;
    this.activeIssues.clear();
    this.lastEmittedAt.clear();
    this.pending = null;
    this.completed = [];
  }

  /** Aggregate stats for the whole set. */
  setStats(): { reps: number; avgScore: number; topIssues: FormIssueId[] } {
    if (this.completed.length === 0) {
      return { reps: 0, avgScore: 0, topIssues: [] };
    }
    const avg = this.completed.reduce((s, r) => s + r.score, 0) / this.completed.length;
    const counts = new Map<FormIssueId, number>();
    for (const r of this.completed) {
      for (const i of r.issues) counts.set(i.id, (counts.get(i.id) ?? 0) + 1);
    }
    const topIssues = [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([id]) => id);
    return { reps: this.completed.length, avgScore: avg, topIssues };
  }

  // ------- internal -------

  private finalizeRep(now: number) {
    if (!this.pending) return null;
    const issues: FormIssue[] = [];

    // Depth.
    if (this.pending.minKneeAngle > SHALLOW_KNEE_ANGLE) {
      issues.push({ id: 'squat_shallow_depth', severity: 'moderate' });
    } else if (this.pending.minKneeAngle > DEEP_KNEE_ANGLE + 10) {
      issues.push({ id: 'squat_shallow_depth', severity: 'minor' });
    }

    // Forward lean.
    if (this.pending.maxLeanDeg > 45) {
      issues.push({ id: 'squat_forward_lean', severity: 'moderate' });
    } else if (this.pending.maxLeanDeg > 35) {
      issues.push({ id: 'squat_forward_lean', severity: 'minor' });
    }

    // Knee valgus.
    if (this.pending.maxValgusRatio > 0.4) {
      issues.push({ id: 'squat_knee_valgus', severity: 'severe' });
    } else if (this.pending.maxValgusRatio > 0.2) {
      issues.push({ id: 'squat_knee_valgus', severity: 'moderate' });
    }

    // Speed.
    const descentMs = (this.pending.bottomAt ?? now) - this.pending.startedAt;
    if (descentMs > 0 && descentMs < FAST_DESCENT_MS) {
      issues.push({ id: 'squat_fast_descent', severity: descentMs < 350 ? 'moderate' : 'minor' });
    }

    const score = scoreFromIssues(issues);
    return {
      score,
      issues,
      durationMs: now - this.pending.startedAt,
    };
  }

  private checkActiveIssues(args: {
    now: number;
    kneeAngle: number;
    leanDeg: number;
    valgusRatio: number;
    events: AnalyzerEvent[];
  }) {
    const { now, kneeAngle, leanDeg, valgusRatio, events } = args;
    // Knees caving in is the most safety-critical — emit live.
    if (valgusRatio > 0.25 && (this.phase === 'descending' || this.phase === 'bottom')) {
      this.maybeEmit(events, now, {
        id: 'squat_knee_valgus',
        severity: valgusRatio > 0.4 ? 'severe' : 'moderate',
      });
    }
    // Excessive lean live.
    if (leanDeg > 45 && this.phase !== 'top') {
      this.maybeEmit(events, now, { id: 'squat_forward_lean', severity: 'moderate' });
    }
    // Update active set (clears when issue is no longer present).
    this.activeIssues = new Set();
    if (valgusRatio > 0.2) this.activeIssues.add('squat_knee_valgus');
    if (leanDeg > 35) this.activeIssues.add('squat_forward_lean');
    if (this.phase === 'bottom' && kneeAngle > SHALLOW_KNEE_ANGLE) {
      this.activeIssues.add('squat_shallow_depth');
    }
  }

  private maybeEmit(events: AnalyzerEvent[], now: number, issue: FormIssue) {
    const last = this.lastEmittedAt.get(issue.id) ?? 0;
    if (now - last < ISSUE_COOLDOWN_MS) return;
    this.lastEmittedAt.set(issue.id, now);
    events.push({ type: 'form_issue', issue, timestamp: now });
  }
}

function avgFinite(...xs: number[]): number {
  const ok = xs.filter((x) => isFinite(x));
  if (ok.length === 0) return NaN;
  return ok.reduce((s, x) => s + x, 0) / ok.length;
}

function mid(a?: { x: number; y: number }, b?: { x: number; y: number }) {
  if (!a || !b) return null;
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function scoreFromIssues(issues: FormIssue[]): number {
  let score = 1;
  for (const i of issues) {
    score -= i.severity === 'severe' ? 0.35 : i.severity === 'moderate' ? 0.2 : 0.08;
  }
  return Math.max(0, Math.min(1, score));
}
