import type { VercelRequest, VercelResponse } from '@vercel/node';
import { z } from 'zod';
import { coachInstructions } from '../../lib/coach';

const DEFAULT_MODEL = process.env.OPENAI_REALTIME_MODEL ?? 'gpt-realtime';
// `marin` and `cedar` are the newer, noticeably more human-sounding voices
// shipped with `gpt-realtime`. `marin` is warmer/feminine, `cedar` is calmer/
// masculine. Override with OPENAI_REALTIME_VOICE in Vercel env if desired.
const DEFAULT_VOICE = process.env.OPENAI_REALTIME_VOICE ?? 'marin';

const SessionRequest = z.object({
  exercise: z.enum(['squat', 'pushup', 'pullup']),
  voice: z.string().optional(),
  targetReps: z.number().int().positive().max(50).optional(),
  athleteName: z.string().min(1).max(40).optional(),
});

/**
 * POST /api/realtime/session
 *
 * Mints a short-lived ephemeral client secret the iOS app uses to open a
 * WebRTC connection to OpenAI Realtime. Uses the GA `/v1/realtime/client_secrets`
 * endpoint (the legacy `/v1/realtime/sessions` endpoint was deprecated and
 * now returns "Unknown beta requested").
 *
 * Response shape mirrors the legacy contract so the iOS client doesn't need
 * to change — we map { value, expires_at, session.id } → { clientSecret,
 * expiresAt, sessionId }.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'OPENAI_API_KEY is not configured' });
  }

  const parsed = SessionRequest.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'invalid request', details: parsed.error.flatten() });
  }

  const { exercise, voice, targetReps, athleteName } = parsed.data;
  const chosenVoice = voice ?? DEFAULT_VOICE;

  try {
    const upstream = await fetch('https://api.openai.com/v1/realtime/client_secrets', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        session: {
          type: 'realtime',
          model: DEFAULT_MODEL,
          instructions: coachInstructions({ exercise, targetReps, athleteName }),
          output_modalities: ['audio'],
          audio: {
            input: {
              // Semantic VAD: detects when the athlete has finished a sentence
              // and auto-creates a response. `eagerness: auto` is responsive
              // enough for across-the-room AirPods mic; `low` was too
              // conservative and missed real user questions mid-workout.
              turn_detection: {
                type: 'semantic_vad',
                eagerness: 'auto',
                create_response: true,
                interrupt_response: true,
              },
              transcription: { model: 'whisper-1' },
            },
            output: { voice: chosenVoice },
          },
        },
      }),
    });

    if (!upstream.ok) {
      const text = await upstream.text();
      console.error('[realtime/session] upstream error', upstream.status, text);
      return res.status(502).json({ error: 'OpenAI session failed', status: upstream.status });
    }

    const body = (await upstream.json()) as {
      value?: string;
      expires_at?: number;
      session?: { id?: string };
    };

    if (!body.value) {
      return res.status(502).json({ error: 'OpenAI response missing client secret' });
    }

    return res.status(200).json({
      sessionId: body.session?.id ?? null,
      clientSecret: body.value,
      expiresAt: body.expires_at ?? null,
      model: DEFAULT_MODEL,
      voice: chosenVoice,
    });
  } catch (err) {
    console.error('[realtime/session] failed', err);
    return res.status(500).json({ error: err instanceof Error ? err.message : 'unknown error' });
  }
}
