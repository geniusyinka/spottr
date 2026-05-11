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

const TOP_ELBOW_ANGLE = 160; // arms ~straight = top of push-up
const BOTTOM_ELBOW_ANGLE = 95; // counts as a deep push-up
const PARTIAL_ELBOW_ANGLE = 115; // didn't get below this = partial

const FAST_REP_MS = 800; // full rep faster than this = uncontrolled
const ISSUE_COOLDOWN_MS = 4000;

interface PendingRep {
  startedAt: number;
  bottomAt: number | null;
  minElbowAngle: number;
  maxHipDropRatio: number; // hips below shoulder-ankle line
  maxElbowFlare: number; // 0..1 ratio of elbow distance from torso
}

export class PushUpAnalyzer implements ExerciseAnalyzer {
  readonly id = 'pushup' as const;

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
    const le = kp.left_elbow;
    const re = kp.right_elbow;
    const lw = kp.left_wrist;
    const rw = kp.right_wrist;
    const lh = kp.left_hip;
    const rh = kp.right_hip;
    const la = kp.left_ankle;
    const ra = kp.right_ankle;

    const upperScore = avgScore(ls, rs, le, re, lw, rw);
    const lineScore = avgScore(ls, rs, lh, rh, la, ra);
    if (
      !isFinite(upperScore) ||
      !isFinite(lineScore) ||
      upperScore < 0.35 ||
      lineScore < 0.3
    ) {
      return events;
    }

    const leftElbow = angleDeg(ls, le, lw);
    const rightElbow = angleDeg(rs, re, rw);
    const elbowAngle = avgFinite(leftElbow, rightElbow);
    if (!isFinite(elbowAngle)) return events;

    // Hip sag heuristic: deviation of hip midpoint from shoulder→ankle line.
    const sM = mid(ls, rs);
    const hM = mid(lh, rh);
    const aM = mid(la, ra);
    let hipDropRatio = 0;
    if (sM && hM && aM) {
      // signed distance from hipMid to line(shoulderMid -> ankleMid), positive = below line
      const dx = aM.x - sM.x;
      const dy = aM.y - sM.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;
      const signed = (hM.x - sM.x) * nx + (hM.y - sM.y) * ny;
      // shoulder-ankle distance as scale; image coords y grows down.
      hipDropRatio = signed / Math.max(0.01, len);
    }

    // Elbow flare: lateral distance from elbow to shoulder, normalized by shoulder width.
    let elbowFlare = 0;
    if (ls && rs && le && re) {
      const shoulderWidth = Math.max(0.0001, Math.hypot(ls.x - rs.x, ls.y - rs.y));
      const leftFlare = Math.abs(le.x - ls.x) / shoulderWidth;
      const rightFlare = Math.abs(re.x - rs.x) / shoulderWidth;
      elbowFlare = Math.max(leftFlare, rightFlare);
    }

    const wasPhase = this.phase;
    if (this.phase === 'top') {
      if (elbowAngle < TOP_ELBOW_ANGLE - 10) {
        this.phase = 'descending';
        this.pending = {
          startedAt: pose.timestamp,
          bottomAt: null,
          minElbowAngle: elbowAngle,
          maxHipDropRatio: hipDropRatio,
          maxElbowFlare: elbowFlare,
        };
      }
    } else if (this.phase === 'descending') {
      if (this.pending) {
        this.pending.minElbowAngle = Math.min(this.pending.minElbowAngle, elbowAngle);
        this.pending.maxHipDropRatio = Math.max(this.pending.maxHipDropRatio, hipDropRatio);
        this.pending.maxElbowFlare = Math.max(this.pending.maxElbowFlare, elbowFlare);
      }
      if (elbowAngle <= BOTTOM_ELBOW_ANGLE + 5) {
        this.phase = 'bottom';
        if (this.pending) this.pending.bottomAt = pose.timestamp;
      } else if (elbowAngle > TOP_ELBOW_ANGLE - 5) {
        this.phase = 'top';
        this.pending = null;
      }
    } else if (this.phase === 'bottom') {
      if (this.pending) {
        this.pending.minElbowAngle = Math.min(this.pending.minElbowAngle, elbowAngle);
        this.pending.maxHipDropRatio = Math.max(this.pending.maxHipDropRatio, hipDropRatio);
        this.pending.maxElbowFlare = Math.max(this.pending.maxElbowFlare, elbowFlare);
      }
      if (elbowAngle > BOTTOM_ELBOW_ANGLE + 15) {
        this.phase = 'ascending';
      }
    } else if (this.phase === 'ascending') {
      if (elbowAngle > TOP_ELBOW_ANGLE - 8) {
        const rep = this.finalizeRep(pose.timestamp);
        if (rep) {
          this.reps += 1;
          this.lastScore = rep.score;
          this.completed.push({ score: rep.score, issues: rep.issues });
          events.push({
            type: 'rep_completed',
            timestamp: pose.timestamp,
            rep: {
              exercise: 'pushup',
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

    this.checkActiveIssues({
      now: pose.timestamp,
      elbowAngle,
      hipDropRatio,
      elbowFlare,
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

  setStats(): { reps: number; avgScore: number; topIssues: FormIssueId[] } {
    if (this.completed.length === 0) return { reps: 0, avgScore: 0, topIssues: [] };
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

  private finalizeRep(now: number) {
    if (!this.pending) return null;
    const issues: FormIssue[] = [];

    if (this.pending.minElbowAngle > PARTIAL_ELBOW_ANGLE) {
      issues.push({ id: 'pushup_partial_rom', severity: 'moderate' });
    } else if (this.pending.minElbowAngle > BOTTOM_ELBOW_ANGLE + 10) {
      issues.push({ id: 'pushup_partial_rom', severity: 'minor' });
    }

    if (this.pending.maxHipDropRatio > 0.07) {
      issues.push({
        id: 'pushup_hip_sag',
        severity: this.pending.maxHipDropRatio > 0.12 ? 'moderate' : 'minor',
      });
    }

    if (this.pending.maxElbowFlare > 1.4) {
      issues.push({ id: 'pushup_elbow_flare', severity: 'moderate' });
    } else if (this.pending.maxElbowFlare > 1.15) {
      issues.push({ id: 'pushup_elbow_flare', severity: 'minor' });
    }

    const totalMs = now - this.pending.startedAt;
    if (totalMs > 0 && totalMs < FAST_REP_MS) {
      issues.push({ id: 'pushup_fast_rep', severity: totalMs < 500 ? 'moderate' : 'minor' });
    }

    const score = scoreFromIssues(issues);
    return { score, issues, durationMs: totalMs };
  }

  private checkActiveIssues(args: {
    now: number;
    elbowAngle: number;
    hipDropRatio: number;
    elbowFlare: number;
    events: AnalyzerEvent[];
  }) {
    const { now, elbowAngle, hipDropRatio, elbowFlare, events } = args;
    if (hipDropRatio > 0.1) {
      this.maybeEmit(events, now, { id: 'pushup_hip_sag', severity: 'moderate' });
    }
    if (elbowFlare > 1.3 && this.phase !== 'top') {
      this.maybeEmit(events, now, { id: 'pushup_elbow_flare', severity: 'moderate' });
    }

    this.activeIssues = new Set();
    if (hipDropRatio > 0.07) this.activeIssues.add('pushup_hip_sag');
    if (elbowFlare > 1.15) this.activeIssues.add('pushup_elbow_flare');
    if (this.phase === 'bottom' && elbowAngle > PARTIAL_ELBOW_ANGLE) {
      this.activeIssues.add('pushup_partial_rom');
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
