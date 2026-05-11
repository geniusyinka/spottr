import { create } from 'zustand';
import type {
  AnalyzerSnapshot,
  ExerciseId,
  FormIssueId,
  RepCompleted,
} from '../lib/exercises/types';

export interface SetSummary {
  exercise: ExerciseId;
  reps: number;
  avgScore: number;
  durationMs: number;
  topIssues: FormIssueId[];
  recommendation: string;
}

interface SessionState {
  exercise: ExerciseId;
  targetReps: number;
  startedAt: number | null;
  snapshot: AnalyzerSnapshot;
  reps: RepCompleted[];
  /** Latest assistant transcript (live cue). */
  currentCue: string;
  summary: SetSummary | null;

  setExercise: (exercise: ExerciseId) => void;
  setTargetReps: (n: number) => void;
  startSet: () => void;
  endSet: (summary: SetSummary) => void;
  reset: () => void;
  updateSnapshot: (s: AnalyzerSnapshot) => void;
  pushRep: (r: RepCompleted) => void;
  setCue: (text: string) => void;
}

const emptySnapshot: AnalyzerSnapshot = {
  phase: 'top',
  reps: 0,
  lastScore: null,
  activeIssues: [],
};

export const useSessionStore = create<SessionState>((set) => ({
  exercise: 'squat',
  targetReps: 10,
  startedAt: null,
  snapshot: emptySnapshot,
  reps: [],
  currentCue: '',
  summary: null,

  setExercise: (exercise) => set({ exercise }),
  setTargetReps: (n) => set({ targetReps: n }),
  startSet: () =>
    set({
      startedAt: Date.now(),
      snapshot: emptySnapshot,
      reps: [],
      currentCue: '',
      summary: null,
    }),
  endSet: (summary) => set({ summary, startedAt: null }),
  reset: () =>
    set({
      startedAt: null,
      snapshot: emptySnapshot,
      reps: [],
      currentCue: '',
      summary: null,
    }),
  updateSnapshot: (s) => set({ snapshot: s }),
  pushRep: (r) => set((state) => ({ reps: [...state.reps, r] })),
  setCue: (text) => set({ currentCue: text }),
}));
