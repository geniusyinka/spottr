import type { VercelRequest, VercelResponse } from '@vercel/node';
import { z } from 'zod';
import { Facts, Moment, liveInput, liveInstructions, livePersona } from '../../lib/live';
import { requirePro } from '../../lib/pro';

// A small, fast model: the whole round trip has to land in about a second.
const LLM_MODEL = process.env.LIVE_LLM_MODEL ?? 'gpt-5.4-mini';
// Reasoning off: a one-line quip doesn't need it. Set to "" for models that reject the parameter.
const LLM_REASONING = process.env.LIVE_LLM_REASONING ?? 'none';
const FISH_MODEL = process.env.FISH_TTS_MODEL ?? 's1';
const FISH_LATENCY = process.env.FISH_TTS_LATENCY ?? 'balanced';

const LineRequest = z.object({
  persona: z.string().max(40),
  moment: Moment,
  facts: Facts,
  athleteName: z.string().min(1).max(40).optional(),
  /** Last few lines spoken this set, so the model doesn't echo itself. */
  recent: z.array(z.string().max(200)).max(8).default([]),
});

/**
 * POST /api/live/line  (Spottr Pro)
 *
 * One LIVE persona line: the model writes it from the moment + facts, Fish
 * Audio voices it with the persona's own voice. Returns the caption and the
 * mp3 as base64 (a 2–3 s line is ~40 KB — not worth streaming yet).
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-RC-App-User-Id');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  const openaiKey = process.env.OPENAI_API_KEY;
  const fishKey = process.env.FISH_AUDIO_API_KEY;
  if (!openaiKey || !fishKey) {
    return res.status(500).json({ error: 'OPENAI_API_KEY and FISH_AUDIO_API_KEY must be configured' });
  }

  const pro = await requirePro(req);
  if (!pro.ok) return res.status(pro.status).json({ error: pro.error });

  const parsed = LineRequest.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'invalid request', details: parsed.error.flatten() });
  }
  const { persona: personaId, moment, facts, athleteName, recent } = parsed.data;
  const persona = livePersona(personaId);
  if (!persona) return res.status(404).json({ error: `no LIVE voice for persona ${personaId}` });

  const started = Date.now();
  let line: string;
  try {
    line = await writeLine({
      apiKey: openaiKey,
      instructions: liveInstructions(personaId, persona, athleteName),
      input: liveInput(moment, facts, recent),
    });
  } catch (err) {
    console.error('LIVE line generation failed', err);
    return res.status(502).json({ error: 'line generation failed' });
  }
  const wroteAt = Date.now();

  let audio: Buffer;
  try {
    audio = await speak({ apiKey: fishKey, text: line, voiceId: persona.voiceId, speed: persona.speed });
  } catch (err) {
    console.error('LIVE line TTS failed', err);
    return res.status(502).json({ error: 'speech failed', line });
  }

  return res.status(200).json({
    line,
    audioBase64: audio.toString('base64'),
    format: 'mp3',
    timings: { writeMs: wroteAt - started, speakMs: Date.now() - wroteAt },
  });
}

async function writeLine(args: { apiKey: string; instructions: string; input: string }): Promise<string> {
  const upstream = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: { Authorization: `Bearer ${args.apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: LLM_MODEL,
      instructions: args.instructions,
      input: args.input,
      ...(LLM_REASONING ? { reasoning: { effort: LLM_REASONING } } : {}),
      max_output_tokens: 400,
      text: {
        format: {
          type: 'json_schema',
          name: 'live_line',
          strict: true,
          schema: {
            type: 'object',
            additionalProperties: false,
            required: ['line'],
            properties: { line: { type: 'string' } },
          },
        },
      },
    }),
  });
  if (!upstream.ok) {
    throw new Error(`OpenAI ${upstream.status}: ${(await upstream.text()).slice(0, 300)}`);
  }
  const body = (await upstream.json()) as {
    output?: Array<{ type: string; content?: Array<{ type: string; text?: string }> }>;
  };
  const text = body.output
    ?.flatMap((item) => item.content ?? [])
    .find((part) => part.type === 'output_text')?.text;
  if (!text) throw new Error('OpenAI returned no text');
  const line = (JSON.parse(text) as { line?: unknown }).line;
  if (typeof line !== 'string' || !line.trim()) throw new Error('OpenAI returned an empty line');
  // Belt and braces on the length rule: a runaway line is dead air mid-set.
  return line.trim().replace(/^["“]|["”]$/g, '').split(/\s+/).slice(0, 16).join(' ');
}

async function speak(args: { apiKey: string; text: string; voiceId: string; speed: number }): Promise<Buffer> {
  const upstream = await fetch('https://api.fish.audio/v1/tts', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${args.apiKey}`,
      'Content-Type': 'application/json',
      model: FISH_MODEL,
    },
    body: JSON.stringify({
      text: args.text,
      reference_id: args.voiceId,
      format: 'mp3',
      mp3_bitrate: 128,
      normalize: true,
      latency: FISH_LATENCY,
      prosody: { speed: args.speed },
    }),
  });
  if (!upstream.ok) {
    throw new Error(`Fish ${upstream.status}: ${(await upstream.text()).slice(0, 300)}`);
  }
  return Buffer.from(await upstream.arrayBuffer());
}
