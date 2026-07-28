import type { VercelRequest, VercelResponse } from '@vercel/node';
import { z } from 'zod';

const DEFAULT_MODEL = process.env.OPENAI_VISION_MODEL ?? 'gpt-5.4';
const MAX_IMAGE_BYTES = 2_500_000;
const MAX_IMAGE_BASE64_LENGTH = Math.ceil((MAX_IMAGE_BYTES * 4) / 3) + 8;

const DescribeRequest = z.object({
  exercise: z.enum(['squat', 'pushup', 'pullup']),
  imageBase64: z.string().min(20).max(MAX_IMAGE_BASE64_LENGTH),
  mimeType: z.enum(['image/jpeg', 'image/png']).default('image/jpeg'),
  clientCapturedAt: z.number().int().positive().optional(),
});

const VisionFacts = z.object({
  summary: z.string(),
  personVisible: z.enum(['yes', 'no', 'unclear']),
  fullBodyVisible: z.enum(['yes', 'no', 'unclear']),
  visibleBodyParts: z.array(z.string()),
  clothing: z.object({
    topColor: z.string(),
    bottomColor: z.string(),
  }),
  hands: z.object({
    visible: z.enum(['yes', 'no', 'unclear']),
    fingersHeldUp: z.number().int().min(-1).max(10),
    confidence: z.enum(['high', 'medium', 'low', 'not_countable']),
  }),
  exerciseSetup: z.enum([
    'squat_standing',
    'squat_kneeling_or_sitting',
    'pushup_plank',
    'pushup_knees',
    'pullup_hanging',
    'not_visible',
    'other',
    'unclear',
  ]),
  formObservations: z.array(z.string()),
  equipment: z.array(z.string()),
  sceneContext: z.string(),
  uncertainties: z.array(z.string()),
});

type VisionFacts = z.infer<typeof VisionFacts>;

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

  const parsed = DescribeRequest.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'invalid request', details: parsed.error.flatten() });
  }

  const { exercise, imageBase64, mimeType, clientCapturedAt } = parsed.data;
  const imageBytes = decodeBase64Image(imageBase64, mimeType);
  if (!imageBytes) {
    return res.status(400).json({ error: 'invalid image data' });
  }
  if (imageBytes.length > MAX_IMAGE_BYTES) {
    return res.status(413).json({
      error: 'image too large',
      maxBytes: MAX_IMAGE_BYTES,
    });
  }

  try {
    const upstream = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: DEFAULT_MODEL,
        input: [
          {
            role: 'user',
            content: [
              {
                type: 'input_text',
                text: [
                  `This is one live camera snapshot from a workout app while the selected exercise is ${exercise}.`,
                  'Extract only facts visible in this image. Do not infer from the selected exercise, pose-tracker data, likely gym context, or previous frames.',
                  'If a detail is blocked, cropped, blurry, too small, or not visible, mark it as unclear or not visible. Never guess clothing colors, finger counts, knee position, equipment, or form.',
                  'For formObservations, include only visual facts a human coach could see in this still frame. Use "not visible" or "unclear" when the snapshot is insufficient.',
                  'For fingersHeldUp, use -1 unless the number of raised fingers is directly countable in the image.',
                  'Do not identify the person or describe identity-sensitive traits. Return JSON only.',
                ].join(' '),
              },
              {
                type: 'input_image',
                image_url: `data:${mimeType};base64,${imageBase64}`,
                detail: imageDetailFor(DEFAULT_MODEL),
              },
            ],
          },
        ],
        text: {
          format: {
            type: 'json_schema',
            name: 'workout_visual_observation',
            strict: true,
            schema: {
              type: 'object',
              additionalProperties: false,
              required: [
                'summary',
                'personVisible',
                'fullBodyVisible',
                'visibleBodyParts',
                'clothing',
                'hands',
                'exerciseSetup',
                'formObservations',
                'equipment',
                'sceneContext',
                'uncertainties',
              ],
              properties: {
                summary: { type: 'string' },
                personVisible: { type: 'string', enum: ['yes', 'no', 'unclear'] },
                fullBodyVisible: { type: 'string', enum: ['yes', 'no', 'unclear'] },
                visibleBodyParts: { type: 'array', items: { type: 'string' } },
                clothing: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['topColor', 'bottomColor'],
                  properties: {
                    topColor: { type: 'string' },
                    bottomColor: { type: 'string' },
                  },
                },
                hands: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['visible', 'fingersHeldUp', 'confidence'],
                  properties: {
                    visible: { type: 'string', enum: ['yes', 'no', 'unclear'] },
                    fingersHeldUp: { type: 'integer', minimum: -1, maximum: 10 },
                    confidence: { type: 'string', enum: ['high', 'medium', 'low', 'not_countable'] },
                  },
                },
                exerciseSetup: {
                  type: 'string',
                  enum: [
                    'squat_standing',
                    'squat_kneeling_or_sitting',
                    'pushup_plank',
                    'pushup_knees',
                    'pullup_hanging',
                    'not_visible',
                    'other',
                    'unclear',
                  ],
                },
                formObservations: { type: 'array', items: { type: 'string' } },
                equipment: { type: 'array', items: { type: 'string' } },
                sceneContext: { type: 'string' },
                uncertainties: { type: 'array', items: { type: 'string' } },
              },
            },
          },
        },
      }),
    });

    if (!upstream.ok) {
      const text = await upstream.text();
      console.error('[vision/describe] upstream error', upstream.status, text);
      return res.status(502).json({ error: 'OpenAI vision failed', status: upstream.status, upstream: text });
    }

    const body = await upstream.json();
    const rawText = extractResponseText(body);
    const facts = parseVisionFacts(rawText);
    if (!facts) {
      console.error('[vision/describe] invalid structured output', rawText);
      return res.status(502).json({ error: 'OpenAI vision returned invalid structured output' });
    }

    return res.status(200).json({
      description: describeFacts(facts),
      facts,
      model: DEFAULT_MODEL,
      capturedAt: clientCapturedAt ?? Date.now(),
      analyzedAt: Date.now(),
    });
  } catch (err) {
    console.error('[vision/describe] failed', err);
    return res.status(500).json({ error: err instanceof Error ? err.message : 'unknown error' });
  }
}

function extractResponseText(body: unknown): string {
  if (typeof body !== 'object' || body === null) return '';
  const direct = (body as { output_text?: unknown }).output_text;
  if (typeof direct === 'string' && direct.trim()) return direct.trim();

  const output = (body as { output?: unknown }).output;
  if (!Array.isArray(output)) return '';

  const parts: string[] = [];
  for (const item of output) {
    if (typeof item !== 'object' || item === null) continue;
    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (typeof part !== 'object' || part === null) continue;
      const text = (part as { text?: unknown }).text;
      if (typeof text === 'string' && text.trim()) parts.push(text.trim());
    }
  }

  return parts.join(' ').trim();
}

function decodeBase64Image(imageBase64: string, mimeType: 'image/jpeg' | 'image/png'): Buffer | null {
  const normalized = imageBase64.replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized)) return null;

  const bytes = Buffer.from(normalized, 'base64');
  if (bytes.length < 1000) return null;

  if (mimeType === 'image/jpeg') {
    return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff ? bytes : null;
  }

  const pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return pngMagic.every((value, index) => bytes[index] === value) ? bytes : null;
}

function imageDetailFor(model: string): 'high' | 'original' {
  return /^gpt-5\.(4|5)(?:-|$)/.test(model) ? 'original' : 'high';
}

function parseVisionFacts(text: string): VisionFacts | null {
  try {
    const parsed = JSON.parse(text) as unknown;
    return VisionFacts.parse(parsed);
  } catch {
    return null;
  }
}

function describeFacts(facts: VisionFacts): string {
  const parts = [
    facts.summary,
    `personVisible=${facts.personVisible}`,
    `fullBodyVisible=${facts.fullBodyVisible}`,
    `top=${facts.clothing.topColor}`,
    `bottom=${facts.clothing.bottomColor}`,
    `hands=${facts.hands.visible}`,
    `fingersHeldUp=${facts.hands.fingersHeldUp >= 0 ? facts.hands.fingersHeldUp : 'not_countable'}`,
    `exerciseSetup=${facts.exerciseSetup}`,
  ];

  if (facts.formObservations.length) {
    parts.push(`form=${facts.formObservations.join('; ')}`);
  }
  if (facts.equipment.length) {
    parts.push(`equipment=${facts.equipment.join(', ')}`);
  }
  if (facts.uncertainties.length) {
    parts.push(`uncertain=${facts.uncertainties.join('; ')}`);
  }

  return parts.join(' | ');
}
