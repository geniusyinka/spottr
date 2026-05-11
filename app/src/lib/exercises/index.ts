import { SquatAnalyzer } from './squat';
import { PushUpAnalyzer } from './pushup';
import type { ExerciseAnalyzer, ExerciseId, FormIssueId } from './types';

export function createAnalyzer(id: ExerciseId): ExerciseAnalyzer {
  return id === 'squat' ? new SquatAnalyzer() : new PushUpAnalyzer();
}

export const EXERCISE_LABELS: Record<ExerciseId, string> = {
  squat: 'Squat',
  pushup: 'Push-up',
};

export const ISSUE_LABELS: Record<FormIssueId, string> = {
  squat_shallow_depth: 'Insufficient depth',
  squat_knee_valgus: 'Knees caving in',
  squat_forward_lean: 'Excessive forward lean',
  squat_fast_descent: 'Descending too fast',
  pushup_hip_sag: 'Hips sagging',
  pushup_partial_rom: 'Partial range of motion',
  pushup_elbow_flare: 'Elbows flaring out',
  pushup_fast_rep: 'Reps too fast',
};

export const ISSUE_COACH_HINT: Record<FormIssueId, string> = {
  squat_shallow_depth: 'Sit deeper into the next rep.',
  squat_knee_valgus: 'Push your knees out, in line with your toes.',
  squat_forward_lean: 'Chest up, weight in your heels.',
  squat_fast_descent: 'Slow the descent — about 2 seconds down.',
  pushup_hip_sag: 'Squeeze your glutes and brace your core.',
  pushup_partial_rom: 'Lower until your chest is near the floor.',
  pushup_elbow_flare: 'Tuck your elbows closer to your ribs.',
  pushup_fast_rep: 'Slow it down for more control.',
};

export type {
  Pose,
  Keypoint,
  KeypointName,
  ExerciseId,
  ExerciseAnalyzer,
  AnalyzerEvent,
  AnalyzerSnapshot,
  FormIssue,
  FormIssueId,
  IssueSeverity,
  RepCompleted,
  RepPhase,
} from './types';
