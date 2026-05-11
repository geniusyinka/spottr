/**
 * Pose-detection contract. We use a simplified MoveNet keypoint set so the
 * analyzers stay framework-agnostic.
 */

export type KeypointName =
  | 'nose'
  | 'left_eye'
  | 'right_eye'
  | 'left_ear'
  | 'right_ear'
  | 'left_shoulder'
  | 'right_shoulder'
  | 'left_elbow'
  | 'right_elbow'
  | 'left_wrist'
  | 'right_wrist'
  | 'left_hip'
  | 'right_hip'
  | 'left_knee'
  | 'right_knee'
  | 'left_ankle'
  | 'right_ankle';

export interface Keypoint {
  name: KeypointName;
  x: number; // normalized 0..1 in image space
  y: number;
  score: number; // confidence 0..1
}

export interface Pose {
  keypoints: Partial<Record<KeypointName, Keypoint>>;
  timestamp: number; // ms
}

export type ExerciseId = 'squat' | 'pushup';

/**
 * Phase of a rep cycle.
 *  - 'top': starting position (standing for squat, plank for push-up)
 *  - 'descending': moving toward bottom
 *  - 'bottom': at the bottom of the rep
 *  - 'ascending': moving back to the top
 */
export type RepPhase = 'top' | 'descending' | 'bottom' | 'ascending';

export type FormIssueId =
  // squat
  | 'squat_shallow_depth'
  | 'squat_knee_valgus'
  | 'squat_forward_lean'
  | 'squat_fast_descent'
  // push-up
  | 'pushup_hip_sag'
  | 'pushup_partial_rom'
  | 'pushup_elbow_flare'
  | 'pushup_fast_rep';

export type IssueSeverity = 'minor' | 'moderate' | 'severe';

export interface FormIssue {
  id: FormIssueId;
  severity: IssueSeverity;
  detail?: string;
}

export interface RepCompleted {
  exercise: ExerciseId;
  index: number; // 1-based
  durationMs: number;
  score: number; // 0..1
  issues: FormIssue[];
}

export interface AnalyzerSnapshot {
  phase: RepPhase;
  reps: number;
  /** Last rep's score, 0..1, or null if no reps yet. */
  lastScore: number | null;
  /** Currently active issues (transient, while user is in the bad position). */
  activeIssues: FormIssueId[];
}

export interface AnalyzerEvent {
  type: 'rep_completed' | 'form_issue' | 'phase_changed';
  rep?: RepCompleted;
  issue?: FormIssue;
  phase?: RepPhase;
  timestamp: number;
}

export interface ExerciseAnalyzer {
  readonly id: ExerciseId;
  /** Feed a pose; returns any events emitted on this frame. */
  update(pose: Pose): AnalyzerEvent[];
  snapshot(): AnalyzerSnapshot;
  reset(): void;
}
