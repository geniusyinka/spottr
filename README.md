# Spottr

> AI gym coach. Phone camera + on-device pose estimation + OpenAI Realtime voice feedback. Put your phone across the room, put your headphones in, work out. The coach watches, counts, calls out form issues, and answers questions while you lift.

[![status](https://img.shields.io/badge/status-prototype-orange)]()
[![license](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

> ⚠️ **Safety disclaimer.** Spottr is a prototype, not medical or professional coaching advice. Form analysis is heuristic and may be wrong. Consult a qualified coach or physician before starting a new exercise program. Stop immediately if you feel pain, dizziness, or instability.

---

## What it does

You pick an exercise (squat, push-up, pull-up), prop your phone where the camera can see your whole body, and start a set. Spottr does the rest:

- **Pose detection runs on-device** (Apple's Vision framework), and occasional compressed snapshots are sent to the backend for semantic visual checks.
- **Reps are counted automatically** from joint angles, with form checks per exercise (e.g. squat depth, knee valgus; push-up hip sag, partial range; pull-up chin-over-bar, kipping).
- **A real-time voice coach** (OpenAI Realtime, `gpt-realtime`) speaks through your headphones. It greets you when the camera locks on, calls out form issues as they happen, gives milestone callouts, and answers questions you ask out loud mid-set.
- **The coach knows what it can and can't see.** It only receives structured movement events — never raw video — and the system prompt makes it answer honestly when asked about things it can't verify ("I can't tell that from the data I have").
- **Two-way voice** via semantic VAD. You can ask "how am I doing?" or "what flags did I get?" and get a real answer based on the actual events.

## Architecture

```
┌──────────────────────────┐         ┌───────────────────────────┐
│  iOS app (SwiftUI)       │         │  Vercel backend (Node/TS) │
│                          │         │                           │
│  AVCaptureSession ─┐     │         │  POST /api/realtime/      │
│                    │     │  HTTPS  │       session             │
│  VNDetectHuman   ──┼────▶│ ──────▶ │  ↓ mints ephemeral key    │
│  BodyPoseRequest   │     │         │  ↓ via OpenAI API         │
│                    │     │         │                           │
│  Squat / Pushup /  │     │         └───────────────────────────┘
│  Pullup analyzers  │     │                  │
│           │        │     │                  │  ephemeral key (~60s)
│           ▼        │     │                  ▼
│  Coach events ─────┼──── WebRTC data channel ────┐
│  (rep_completed,   │                             │
│   form_issue, …)   │                             ▼
│                    │                  ┌──────────────────────┐
│  Mic uplink ───────┼──── WebRTC audio │ OpenAI Realtime API  │
│                    │                  │  gpt-realtime        │
│  Coach voice ◀─────┼──── WebRTC audio │  semantic_vad        │
│  (AirPods/speaker) │                  └──────────────────────┘
└──────────────────────────┘
```

**Trust boundary.** The long-lived `OPENAI_API_KEY` lives only on the Vercel backend. The phone only ever sees short-lived ephemeral session tokens. If someone reverse-engineers the IPA, they get nothing useful.

## Repo layout

```
spottr/
├── server/        # Vercel-deployed Node/TS backend that mints OpenAI Realtime
│                  #   ephemeral keys. Holds the long-lived OPENAI_API_KEY.
├── ios-native/    # SwiftUI iOS app. Vision-based pose detection, native WebRTC.
│                  #   This is the recommended build path.
└── app/           # Legacy React Native/Expo prototype. Same coaching pipeline
                   #   but pose detection is stubbed (Expo SDK 51 vs Xcode 26
                   #   incompatibility). Retained as a reference implementation.
```

## Quick start

You need:

- macOS with Xcode 16+ (the Vision pose model requires Apple's SDK)
- Node 20+
- An OpenAI account with Realtime API access (the model is metered separately from chat)
- An iPhone that supports iOS 16+ (Vision pose works well on iPhone 13+)
- A Vercel account (free tier is fine for personal use)

### 1. Deploy the backend

```bash
cd server
npm install
npm install -g vercel
vercel link               # create or link a Vercel project
vercel env add OPENAI_API_KEY production
vercel env add OPENAI_API_KEY development
vercel deploy --prod
```

This gives you a public URL like `https://<your-project>.vercel.app`. Verify it:

```bash
curl https://<your-project>.vercel.app/api/health
# → {"ok":true,"service":"spottr-server"}
```

Optional smoke test that exercises the coach over a fake event sequence (mints a key, opens a real WebSocket to OpenAI, prints what the coach says):

```bash
SPOTTR_BACKEND=https://<your-project>.vercel.app node test/coach-smoke.mjs
```

### 2. Build the iOS app

```bash
cd ios-native
brew install xcodegen          # one-time
xcodegen generate              # generates Spottr.xcodeproj from project.yml
```

Update `BackendConfig.baseURL` in `Spottr/Realtime/BackendClient.swift` to point at your Vercel URL (the repo's default points at the maintainer's deployment).

Open Xcode, set your development team in **Signing & Capabilities**, plug in your iPhone, and run. For CLI builds:

```bash
xcodebuild -project Spottr.xcodeproj -scheme Spottr \
  -configuration Debug \
  -destination "id=<your-iPhone-UDID>" \
  -allowProvisioningUpdates \
  build
```

You can find your UDID with `xcrun xctrace list devices`.

### 3. First run

Open Spottr on your phone:

1. Edit **Your name** on the home screen (defaults to "Yinka" because the maintainer is lazy — it's saved across launches).
2. **Start a set → pick an exercise → target reps → Start session**.
3. Grant **Camera**, **Microphone**, and **Local Network** permissions when prompted.
4. Walk to your workout spot. The HUD says "Looking for you…" until the camera locks on, then flips to "Ready when you are" and the coach greets you through your headphones.
5. Do reps. Counter ticks; coach calls out form issues and milestones.

## What the coach actually does

The coach is `gpt-realtime` driven by:

1. **The system prompt in `server/lib/coach.ts`** — sets tone (terse, no hype, default-silent), lists the exact data it has access to, and specifies behavior per event type.
2. **Structured movement events** from the iOS app over the WebRTC data channel:
   - `set_ready` — camera locked onto the athlete (triggers greeting)
   - `set_started` — first rep detected (silent)
   - `rep_completed` — index, duration, score, issues
   - `form_issue` — live form flag mid-rep
   - `set_finished` — set summary (triggers wrap-up)
   - `coach_should_speak` — explicit "say something now" trigger
3. **Your voice**, transcribed and turn-detected via `semantic_vad` with `eagerness: low` so it ignores grunts and breathing.

The realtime coach receives two streams: structured pose/form events, plus strict `visual_observation` facts produced from actual camera snapshots. Ask it "what variant am I doing" or "what am I wearing" and it should answer from the latest visual snapshot only; if the snapshot is missing, stale, blocked, or unclear, it must say it cannot see that detail clearly.

## Privacy

- Camera frames are passed to `VNDetectHumanBodyPoseRequest` in-memory and discarded on-device for pose tracking.
- Every few seconds, a compressed JPEG snapshot is sent to `/api/vision/describe`, which sends it to OpenAI's Responses API for visual analysis. The backend returns structured visual facts to the realtime coach; snapshots are not stored by this app.
- Session recording is off by default. If enabled before a set, iOS records the workout screen, microphone audio, and app audio, saves the movie locally, requests add-only Photos permission, and writes the recording to Photos when allowed.
- Structured numbers/enums and structured visual facts flow over the realtime data channel to OpenAI.
- Microphone audio is uploaded to OpenAI Realtime over WebRTC for the voice coach. Toggle it off via `realtime.setMicEnabled(false)` if you want to mute.
- Long-lived API keys stay on the backend; the phone only sees ~60s ephemeral session tokens.

## Known limitations

- Pose detection is single-person, front- or side-facing. Group workouts confuse it.
- Form analysis is heuristic and not exhaustive. A rep can be "clean" by the analyzer but bad by a real coach's eye (and vice versa).
- The coach can't see exercise variants (knees-down push-ups, modified ranges, weight increments) — it only sees the structured events. It will admit this when asked.
- iOS only for now. The pose stack is built on Apple's Vision framework.
- Pull-up detection requires a clear view of the bar; if the phone is too low you may miss the chin-over-bar check.

## Built with

- [OpenAI Realtime API](https://platform.openai.com/docs/guides/realtime) (`gpt-realtime`, `marin` voice)
- Apple [Vision](https://developer.apple.com/documentation/vision) framework for pose
- [stasel/WebRTC](https://github.com/stasel/WebRTC) Swift Package
- [Vercel](https://vercel.com) for the backend (Node/TS Functions)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) for the Xcode project

## Contributing

Issues and PRs welcome. A few good first contributions:

- New exercise analyzers (lunges, deadlifts, rows). Pattern is in `ios-native/Spottr/Analyzers/`.
- Tuning the existing analyzer thresholds — they're heuristic and could use real-data calibration.
- Better posture variant detection (knees-down push-up, incline, etc.) so the coach has more context.
- An Android port. The pose layer would need MediaPipe or ML Kit instead of Vision; the rest of the architecture is portable.

When opening a PR please include a short note about what you tested it against (which iPhone, which exercise) since the camera-based behavior is hard to unit-test.

## License

MIT — see [LICENSE](./LICENSE).
