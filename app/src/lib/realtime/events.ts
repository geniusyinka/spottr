import type { ExerciseId, FormIssueId, RepCompleted } from '../exercises/types';

/**
 * Events the client pushes into the Realtime data channel as
 * `conversation.item.create` messages with role=user. We use the user role
 * (not system, which the API rejects on conversation items) and prefix the
 * payload with "[event]" so the model can distinguish observations from
 * spoken utterances.
 */

export interface CoachEventBase {
  type: string;
  timestamp: number;
}

export interface SetStartedEvent extends CoachEventBase {
  type: 'set_started';
  exercise: ExerciseId;
  targetReps?: number;
}

export interface RepCompletedEvent extends CoachEventBase {
  type: 'rep_completed';
  rep: RepCompleted;
}

export interface FormIssueEvent extends CoachEventBase {
  type: 'form_issue';
  exercise: ExerciseId;
  issue: FormIssueId;
  severity: 'minor' | 'moderate' | 'severe';
}

export interface SetFinishedEvent extends CoachEventBase {
  type: 'set_finished';
  exercise: ExerciseId;
  reps: number;
  avgScore: number;
  durationMs: number;
  topIssues: FormIssueId[];
}

export interface CoachShouldSpeakEvent extends CoachEventBase {
  type: 'coach_should_speak';
  reason: string;
}

export type CoachEvent =
  | SetStartedEvent
  | RepCompletedEvent
  | FormIssueEvent
  | SetFinishedEvent
  | CoachShouldSpeakEvent;

/** Build the Realtime "conversation.item.create" payload that wraps a coach event. */
export function buildCoachEventMessage(event: CoachEvent) {
  return {
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role: 'user',
      content: [
        {
          type: 'input_text',
          text: `[event] ${JSON.stringify(event)}`,
        },
      ],
    },
  };
}

/**
 * Ask the model to produce an audio + text response.
 *
 * We deliberately do NOT pass per-response `instructions` here. Per-response
 * instructions REPLACE the session-level prompt, so passing them would make
 * the model lose its tone, "1-6 words" rule, and allowed-cue list. The
 * session prompt already covers what to do for each event type — we just need
 * to trigger a turn.
 */
export function buildResponseCreate() {
  return {
    type: 'response.create',
    response: {
      modalities: ['audio', 'text'],
    },
  };
}
