import { ISSUE_COACH_HINT, ISSUE_LABELS } from './exercises';
import type { FormIssueId, RepCompleted } from './exercises/types';
import type { SetSummary } from '../state/sessionStore';

export function buildSetSummary(
  exercise: SetSummary['exercise'],
  reps: RepCompleted[],
  durationMs: number,
): SetSummary {
  if (reps.length === 0) {
    return {
      exercise,
      reps: 0,
      avgScore: 0,
      durationMs,
      topIssues: [],
      recommendation: 'No reps detected — try positioning yourself fully in frame and starting again.',
    };
  }
  const avgScore = reps.reduce((s, r) => s + r.score, 0) / reps.length;

  const counts = new Map<FormIssueId, number>();
  for (const r of reps) for (const i of r.issues) counts.set(i.id, (counts.get(i.id) ?? 0) + 1);
  const topIssues = [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([id]) => id);

  const recommendation = nextSetRecommendation(reps.length, avgScore, topIssues);
  return { exercise, reps: reps.length, avgScore, durationMs, topIssues, recommendation };
}

function nextSetRecommendation(reps: number, avgScore: number, topIssues: FormIssueId[]): string {
  if (avgScore >= 0.85 && topIssues.length === 0) {
    return `Solid set — ${reps} clean reps. Try ${reps + 2} next set with the same tempo.`;
  }
  if (topIssues.length > 0) {
    const primary = topIssues[0];
    if (primary) {
      return `Focus on: ${ISSUE_LABELS[primary]}. ${ISSUE_COACH_HINT[primary]}`;
    }
  }
  if (avgScore < 0.6) {
    return 'Drop the rep count next set and prioritize controlled, full-range reps.';
  }
  return 'Keep the same target next set and concentrate on tempo.';
}
