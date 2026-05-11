import {
  RTCPeerConnection,
  mediaDevices,
  type MediaStream,
  type RTCSessionDescription,
} from 'react-native-webrtc';

// `react-native-webrtc` does not export RTCDataChannel as a type alias; the
// instance type is the return of `RTCPeerConnection.createDataChannel`.
type RTCDataChannel = ReturnType<RTCPeerConnection['createDataChannel']>;

import { BACKEND_URL } from '../../config';
import { buildCoachEventMessage, buildResponseCreate, type CoachEvent } from './events';
import type { ExerciseId } from '../exercises/types';

interface SessionResponse {
  sessionId: string | null;
  clientSecret: string;
  expiresAt: number;
  model: string;
  voice: string;
}

export interface RealtimeClientOptions {
  exercise: ExerciseId;
  targetReps?: number;
  /** Streaming assistant transcript (delta-accumulated). */
  onTranscript?: (text: string) => void;
  /** Connection-state changes. */
  onState?: (state: RealtimeState) => void;
  /** Surfaced when the API or transport fails. */
  onError?: (error: { source: 'api' | 'transport'; message: string; raw?: unknown }) => void;
  /** Toggle verbose logging of every server event (default: __DEV__). */
  debug?: boolean;
}

export type RealtimeState =
  | 'idle'
  | 'fetching_session'
  | 'connecting'
  | 'connected'
  | 'speaking'
  | 'error'
  | 'closed';

const DEBUG_DEFAULT = typeof __DEV__ === 'boolean' ? __DEV__ : false;

/**
 * Realtime client using WebRTC. The audio track from the model is routed to
 * the device speaker automatically by react-native-webrtc.
 *
 * Wire-level contract:
 *   - We DO NOT use server VAD. The session is created with `turn_detection: null`
 *     so the user's mic is uploaded continuously but never auto-triggers a turn.
 *     The client decides when to speak by sending `response.create`.
 *   - Coach events are sent as `conversation.item.create` with `role: 'user'`,
 *     prefixed with `[event]`, so the model treats them as observations.
 *   - Per-response `instructions` are NEVER set, because that would override
 *     the session-level prompt and break tone.
 */
export class RealtimeClient {
  private pc: RTCPeerConnection | null = null;
  private dc: RTCDataChannel | null = null;
  private localStream: MediaStream | null = null;
  private state: RealtimeState = 'idle';
  private currentTranscript = '';
  private opts: RealtimeClientOptions;
  private debug: boolean;
  /** Pending events queued before the data channel is open. */
  private pendingEvents: Array<{ event: CoachEvent; requestSpeech: boolean }> = [];

  constructor(opts: RealtimeClientOptions) {
    this.opts = opts;
    this.debug = opts.debug ?? DEBUG_DEFAULT;
  }

  async connect(): Promise<void> {
    try {
      this.setState('fetching_session');
      const session = await fetchSession(this.opts.exercise, this.opts.targetReps);

      this.setState('connecting');
      const pc = new RTCPeerConnection({
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
      });
      this.pc = pc;

      // Surface ICE / connection failures to the caller.
      pc.addEventListener('iceconnectionstatechange', () => {
        const s = pc.iceConnectionState;
        this.log('iceConnectionState', s);
        if (s === 'failed' || s === 'disconnected') {
          this.opts.onError?.({ source: 'transport', message: `ICE ${s}` });
        }
      });

      // Mic input. Continuous upload — no VAD, so audio is captured but never
      // turns into a model response unless we explicitly call response.create.
      const stream = await mediaDevices.getUserMedia({ audio: true, video: false });
      this.localStream = stream as unknown as MediaStream;
      for (const track of (stream as unknown as MediaStream).getAudioTracks()) {
        pc.addTrack(track, stream as unknown as MediaStream);
      }

      // Data channel for events.
      const dc = pc.createDataChannel('oai-events');
      this.dc = dc;
      dc.addEventListener('open', () => {
        this.log('dc open');
        this.setState('connected');
        // Initial event: tell the model the set has started.
        this.sendEventInternal({
          type: 'set_started',
          exercise: this.opts.exercise,
          targetReps: this.opts.targetReps,
          timestamp: Date.now(),
        });
        // Drain anything queued during connect.
        for (const queued of this.pendingEvents) {
          this.sendEventInternal(queued.event, queued.requestSpeech);
        }
        this.pendingEvents = [];
      });
      dc.addEventListener('message', (e) => {
        const data = (e as unknown as { data: unknown }).data;
        const text = typeof data === 'string' ? data : '';
        if (!text) return;
        try {
          const msg = JSON.parse(text);
          this.handleServerEvent(msg);
        } catch (err) {
          this.log('non-JSON dc message', text.slice(0, 200), err);
        }
      });
      dc.addEventListener('close', () => {
        this.log('dc close');
        this.setState('closed');
      });

      // Offer / answer.
      const offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);

      const sdpResp = await fetch(
        `https://api.openai.com/v1/realtime?model=${encodeURIComponent(session.model)}`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${session.clientSecret}`,
            'Content-Type': 'application/sdp',
          },
          body: offer.sdp ?? '',
        },
      );
      if (!sdpResp.ok) {
        const body = await sdpResp.text().catch(() => '');
        this.setState('error');
        const message = `Realtime SDP exchange failed: ${sdpResp.status} ${body.slice(0, 200)}`;
        this.opts.onError?.({ source: 'api', message });
        throw new Error(message);
      }
      const answerSdp = await sdpResp.text();
      await pc.setRemoteDescription({
        type: 'answer',
        sdp: answerSdp,
      } as RTCSessionDescription);
    } catch (err) {
      this.setState('error');
      const message = err instanceof Error ? err.message : 'unknown realtime connect error';
      this.opts.onError?.({ source: 'transport', message, raw: err });
      throw err;
    }
  }

  /** Send a coach event over the data channel. Optionally trigger speech. */
  sendEvent(event: CoachEvent, requestSpeech = false) {
    if (!this.dc || this.dc.readyState !== 'open') {
      // Connection not yet up. Queue and replay when it opens.
      this.pendingEvents.push({ event, requestSpeech });
      return;
    }
    this.sendEventInternal(event, requestSpeech);
  }

  /** Explicitly ask the model to speak now. */
  requestSpeech(reason: string) {
    this.sendEvent({ type: 'coach_should_speak', reason, timestamp: Date.now() }, true);
  }

  setMicEnabled(enabled: boolean) {
    if (!this.localStream) return;
    for (const t of this.localStream.getAudioTracks()) t.enabled = enabled;
  }

  close() {
    try {
      this.dc?.close();
    } catch {
      /* noop */
    }
    try {
      this.localStream?.getTracks().forEach((t) => t.stop());
    } catch {
      /* noop */
    }
    try {
      this.pc?.close();
    } catch {
      /* noop */
    }
    this.dc = null;
    this.pc = null;
    this.localStream = null;
    this.setState('closed');
  }

  getState(): RealtimeState {
    return this.state;
  }

  // ---- internal ----

  private sendEventInternal(event: CoachEvent, requestSpeech = false) {
    if (!this.dc || this.dc.readyState !== 'open') return;
    const item = buildCoachEventMessage(event);
    this.log('->', item.type, event.type);
    this.dc.send(JSON.stringify(item));
    if (requestSpeech) {
      const req = buildResponseCreate();
      this.log('->', req.type);
      this.dc.send(JSON.stringify(req));
    }
  }

  private setState(s: RealtimeState) {
    if (this.state === s) return;
    this.state = s;
    this.opts.onState?.(s);
  }

  private log(...args: unknown[]) {
    if (!this.debug) return;
    // eslint-disable-next-line no-console
    console.log('[realtime]', ...args);
  }

  private handleServerEvent(msg: {
    type?: string;
    delta?: string;
    transcript?: string;
    error?: { type?: string; code?: string; message?: string; param?: string };
  }) {
    if (!msg.type) return;

    // Always log unknown / important events in debug.
    if (
      msg.type !== 'response.audio_transcript.delta' &&
      msg.type !== 'response.audio.delta' &&
      msg.type !== 'output_audio_buffer.audio.delta'
    ) {
      this.log('<-', msg.type);
    }

    switch (msg.type) {
      case 'error': {
        const m = msg.error?.message ?? 'unknown realtime error';
        this.log('<- error', msg.error);
        this.opts.onError?.({ source: 'api', message: m, raw: msg.error });
        break;
      }
      case 'response.created':
        this.currentTranscript = '';
        this.setState('speaking');
        break;
      case 'response.audio_transcript.delta':
        if (typeof msg.delta === 'string') {
          this.currentTranscript += msg.delta;
          this.opts.onTranscript?.(this.currentTranscript);
        }
        break;
      case 'response.audio_transcript.done':
        if (typeof msg.transcript === 'string') {
          this.opts.onTranscript?.(msg.transcript);
        }
        break;
      case 'response.done':
        this.setState('connected');
        break;
      default:
        break;
    }
  }
}

async function fetchSession(exercise: ExerciseId, targetReps?: number): Promise<SessionResponse> {
  const r = await fetch(`${BACKEND_URL}/api/realtime/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ exercise, targetReps }),
  });
  if (!r.ok) {
    const text = await r.text().catch(() => '');
    throw new Error(`Backend session error ${r.status}: ${text}`);
  }
  return (await r.json()) as SessionResponse;
}
