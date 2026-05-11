/**
 * End-to-end smoke test for the Realtime coach.
 *
 *   node test/coach-smoke.mjs
 *
 * Mints an ephemeral key via the live Vercel deployment, opens a WebSocket
 * to OpenAI Realtime, fires a sequence of coach events, and prints the audio
 * transcript the model produces. Useful for verifying prompt changes without
 * having to do an actual workout.
 */

const BACKEND = process.env.SPOTTR_BACKEND ?? 'https://spottr-yunggenius-projects.vercel.app';
const NAME = process.env.SPOTTR_NAME ?? 'Yinka';
const EXERCISE = process.env.SPOTTR_EXERCISE ?? 'pushup';

const ts = () => Date.now();

async function mintSession() {
  const r = await fetch(`${BACKEND}/api/realtime/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ exercise: EXERCISE, targetReps: 10, athleteName: NAME }),
  });
  if (!r.ok) throw new Error(`mint failed: ${r.status} ${await r.text()}`);
  return r.json();
}

function userEvent(event) {
  return {
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role: 'user',
      content: [{ type: 'input_text', text: `[event] ${JSON.stringify(event)}` }],
    },
  };
}

function userText(text) {
  return {
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role: 'user',
      content: [{ type: 'input_text', text }],
    },
  };
}

const responseCreate = { type: 'response.create', response: { output_modalities: ['audio'] } };

async function main() {
  console.log(`[smoke] minting session at ${BACKEND}…`);
  const session = await mintSession();
  console.log(`[smoke] model=${session.model} voice=${session.voice}`);

  const ws = new WebSocket(
    `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(session.model)}`,
    {
      headers: {
        Authorization: `Bearer ${session.clientSecret}`,
      },
    },
  );

  // Sequence of (description, payload) tuples to fire in order.
  const sequence = [
    ['set_ready', userEvent({ type: 'set_ready', exercise: EXERCISE, targetReps: 10, timestamp: ts() })],
    ['<response>', responseCreate],
    ['ask: what are you seeing', userText('What are you seeing right now?')],
    ['<response>', responseCreate],
    ['rep 1 clean', userEvent({ type: 'rep_completed', rep: { exercise: EXERCISE, index: 1, durationMs: 2200, score: 0.92, issues: [] }, timestamp: ts() })],
    ['rep 2 with shallow', userEvent({ type: 'rep_completed', rep: { exercise: EXERCISE, index: 2, durationMs: 1900, score: 0.7, issues: [{ id: 'pushup_partial_rom', severity: 'moderate' }] }, timestamp: ts() })],
    ['<response>', responseCreate],
    ['ask: knees on floor variant', userText('Is it ok that I have my knees on the floor?')],
    ['<response>', responseCreate],
    ['ask: how am I doing', userText('How am I doing so far?')],
    ['<response>', responseCreate],
  ];

  let cursor = 0;
  let collected = '';
  let responseInFlight = false;

  function advance() {
    if (cursor >= sequence.length) {
      console.log('\n[smoke] sequence complete, closing.');
      ws.close();
      return;
    }
    const [label, payload] = sequence[cursor++];
    if (payload.type === 'response.create') {
      console.log(`\n>>> ${label}`);
      responseInFlight = true;
      collected = '';
      process.stdout.write('   coach: ');
    } else {
      console.log(`\n[push] ${label}`);
    }
    ws.send(JSON.stringify(payload));
    if (payload.type !== 'response.create') {
      // Non-trigger events: advance immediately to next step.
      setTimeout(advance, 50);
    }
  }

  ws.addEventListener('open', () => {
    console.log('[smoke] ws open');
    setTimeout(advance, 200);
  });

  ws.addEventListener('message', (e) => {
    let msg;
    try { msg = JSON.parse(e.data); } catch { return; }
    const t = msg.type ?? '';
    // Only forward TRANSCRIPT deltas (text), never audio (base64 PCM).
    if (t.includes('transcript') && t.endsWith('.delta') && typeof msg.delta === 'string') {
      process.stdout.write(msg.delta);
      collected += msg.delta;
      return;
    }
    if (t === 'response.done') {
      responseInFlight = false;
      setTimeout(advance, 250);
      return;
    }
    if (t === 'error') {
      console.error(`\n[error] ${msg.error?.message ?? JSON.stringify(msg.error)}`);
      return;
    }
    // Trace only non-audio events; audio events are noisy.
    if (process.env.SPOTTR_TRACE && !t.includes('audio.delta') && !t.includes('output_audio.delta')) {
      console.log(`\n[event] ${t}`);
    }
  });

  ws.addEventListener('close', () => {
    console.log('\n[smoke] ws closed');
    process.exit(0);
  });

  ws.addEventListener('error', (e) => {
    console.error('[ws error]', e?.message ?? e);
    process.exit(1);
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
