import { z } from 'zod';
import personaSheet from './personas.generated.json';

/**
 * LIVE personas (Spottr Pro): the same characters as the pre-rendered packs,
 * but each line is written for the moment from what the phone saw, then voiced
 * by Fish Audio in the persona's own voice.
 *
 * The app decides *when* to talk (a "moment") and sends the facts it has;
 * this module turns that into one short line. Facts are the only source of
 * truth — the model may not invent numbers or observations.
 */

export type LivePersona = {
  name: string;
  brief: string;
  voiceId: string;
  speed: number;
  examples: string[];
};

const PERSONAS = personaSheet as Record<string, LivePersona>;
export const LIVE_PERSONA_IDS = Object.keys(PERSONAS);

export function livePersona(id: string): LivePersona | undefined {
  return PERSONAS[id];
}

/** Why the app wants a line right now. */
export const Moment = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('set_start') }),
  z.object({ kind: z.literal('exercise_detected') }),
  z.object({ kind: z.literal('rep_milestone') }),
  z.object({ kind: z.literal('pace_drop') }),
  z.object({ kind: z.literal('form_issue'), issue: z.string().max(60), hint: z.string().max(120).optional() }),
  z.object({ kind: z.literal('form_fixed'), issue: z.string().max(60) }),
  z.object({ kind: z.literal('closing_on_last_set'), repsToGo: z.number().int().min(0).max(100) }),
  z.object({ kind: z.literal('beat_last_set') }),
  z.object({ kind: z.literal('stalled') }),
  z.object({ kind: z.literal('set_complete') }),
  z.object({ kind: z.literal('filler') }),
]);
export type Moment = z.infer<typeof Moment>;

/** What the phone knows about the set — all on-device measurements. */
export const Facts = z.object({
  exercise: z.string().max(40).optional(),
  reps: z.number().int().min(0).max(1000).optional(),
  setNumber: z.number().int().min(1).max(100).optional(),
  elapsedSeconds: z.number().min(0).max(7200).optional(),
  /** Mean seconds per rep over the last few reps. */
  secondsPerRep: z.number().min(0).max(60).optional(),
  /** Same, for the first reps of the set — compare to see fatigue. */
  openingSecondsPerRep: z.number().min(0).max(60).optional(),
  lastSetReps: z.number().int().min(0).max(1000).optional(),
  bestReps: z.number().int().min(0).max(1000).optional(),
  /** Form issue currently showing, if any. */
  activeIssue: z.string().max(60).optional(),
  /** 1 = chill, 2 = standard, 3 = unhinged — the user's intensity dial. */
  intensity: z.number().int().min(1).max(3).default(2),
});
export type Facts = z.infer<typeof Facts>;

const MOMENT_BRIEF: Record<Moment['kind'], string> = {
  set_start: 'The set is starting. Fire them up for it.',
  exercise_detected: 'The camera just recognized the exercise. Call it out in character.',
  rep_milestone: 'They just hit the rep count in the facts. Acknowledge that number.',
  pace_drop: 'Their reps are slowing down — fatigue is setting in. Push them through it.',
  form_issue: 'The form check just flagged a problem. Give ONE short correction, in character.',
  form_fixed: 'They just fixed a form problem the check had flagged. Praise the fix specifically.',
  closing_on_last_set: 'They are close to their last set\'s rep count. Tell them how many to go, from the facts.',
  beat_last_set: 'They just beat their last set\'s reps. Celebrate it.',
  stalled: 'They have stopped moving mid-set. Get them going again, or check they are okay to continue.',
  set_complete: 'The set just ended. React to what they did, using the facts.',
  filler: 'Nothing specific happened. Keep the energy up without repeating yourself.',
};

const CONTENT_RULES: Record<string, string> = {
  trash_talker:
    'Explicit-lite insult comedy: mild profanity is fine, slurs never. Roast their effort, never their identity, body, or appearance. Affection underneath.',
};
const DEFAULT_CONTENT_RULE = 'PG-13 and gym-safe. No profanity.';

export function liveInstructions(personaId: string, persona: LivePersona, athleteName?: string): string {
  const name = athleteName?.trim();
  return [
    `You are ${persona.name}, a spotter voice in a workout app, speaking out loud to someone mid-workout.`,
    `Voice and character: ${persona.brief}`,
    '',
    'Lines you have said before — match this voice, rhythm, and energy exactly, but never reuse them:',
    ...persona.examples.map((line) => `- ${line}`),
    '',
    'Rules:',
    '- Write ONE line to say right now. 4 to 12 words. It is spoken aloud, not read.',
    '- Write speech: fragments are fine; ellipses and em dashes are breath beats; CAPS for a shout, sparingly. No emojis, no hashtags, no stage directions, no quotation marks.',
    '- React to the moment and the facts you are given. Use numbers only when they appear in the facts, exactly as given. Never invent reps, times, weights, records, or anything you cannot see.',
    '- No medical or injury advice beyond the one form cue the moment asks for.',
    `- Content: ${CONTENT_RULES[personaId] ?? DEFAULT_CONTENT_RULE}`,
    '- Intensity 1 is calm, 2 is standard, 3 is unhinged. Match the intensity in the facts.',
    '- Do not repeat or closely echo any line in "recently said".',
    name
      ? `- The athlete's name is ${name}. Use it at most once every few lines, never every line.`
      : '- You do not know the athlete\'s name; do not make one up.',
  ].join('\n');
}

/** What each fact means, so the model can't misread one (e.g. setNumber 2 as "two sets"). */
const FACT_GLOSSARY: Record<keyof Facts, string> = {
  exercise: 'the exercise being done',
  reps: 'reps completed so far in THIS set',
  setNumber: 'which set of the session this is (2 = their second set)',
  elapsedSeconds: 'seconds since this set started',
  secondsPerRep: 'average seconds per rep over the last few reps',
  openingSecondsPerRep: 'average seconds per rep at the start of this set (higher now = slowing down)',
  lastSetReps: 'reps they did in their previous set',
  bestReps: 'their best-ever reps in one set of this exercise',
  activeIssue: 'a form problem showing right now',
  intensity: 'how intense to be, 1 to 3',
};

export function liveInput(moment: Moment, facts: Facts, recent: string[]): string {
  const known = Object.entries(facts).filter(([, value]) => value !== undefined) as [keyof Facts, unknown][];
  return [
    `Moment: ${MOMENT_BRIEF[moment.kind]}`,
    moment.kind === 'form_issue'
      ? `Flagged issue: ${moment.issue}${moment.hint ? ` (the fix: ${moment.hint})` : ''}`
      : moment.kind === 'form_fixed'
        ? `Fixed issue: ${moment.issue}`
        : moment.kind === 'closing_on_last_set'
          ? `Reps to go to match last set: ${moment.repsToGo}`
          : '',
    'Facts:',
    ...known.map(([key, value]) => `- ${key} = ${JSON.stringify(value)} (${FACT_GLOSSARY[key]})`),
    `Recently said: ${recent.length ? recent.map((line) => `"${line}"`).join(' | ') : '(nothing yet)'}`,
  ]
    .filter(Boolean)
    .join('\n');
}
