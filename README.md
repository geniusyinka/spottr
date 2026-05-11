# Spottr

AI gym coach: phone camera + on-device pose estimation + OpenAI Realtime voice feedback.

> ⚠️ **Safety disclaimer.** Spottr is a prototype, not medical or professional coaching advice. Form analysis is heuristic and may be wrong. Consult a qualified coach or physician before starting a new exercise program. Stop immediately if you feel pain, dizziness, or instability.

## Repo layout

```
spottr/
├── app/        # Expo React Native + TypeScript mobile app
└── server/     # Node.js + TypeScript backend (mints OpenAI Realtime ephemeral keys)
```

## Quick start

### 1. Backend

```bash
cd server
cp .env.example .env          # add your OPENAI_API_KEY
npm install
npm run dev                   # runs at http://localhost:8787
```

### 2. Mobile app

```bash
cd app
cp .env.example .env          # set EXPO_PUBLIC_BACKEND_URL to your machine's LAN IP
npm install
npx expo prebuild             # generates native projects (one-time)
npx expo run:ios              # or: npx expo run:android
```

> Spottr uses `react-native-webrtc` and TF.js native modules, so it requires a **dev client** build — Expo Go will not work.

## Privacy & data handling

- Video frames are **never persisted** by default. Only structured movement events (rep counts, joint angles, form flags) are sent to the AI coach.
- Frame analysis (sending images to a vision model) is opt-in only and disabled by default.
- The OpenAI API key is held server-side. The mobile app receives only short-lived ephemeral session tokens.

## How it works

1. The user picks an exercise (squat or push-up).
2. The phone camera streams to an on-device MoveNet pose detector.
3. A per-exercise analyzer computes joint angles, counts reps, and emits form events.
4. The app holds a WebRTC connection to OpenAI Realtime, authed via an ephemeral key from `/api/realtime/session`.
5. Form events are pushed over the data channel; the model speaks short cues back through the audio track.
6. At end of set, the app summarizes reps, average score, top issues, and a next-set recommendation.

See `app/src/lib/exercises/` for the analyzer logic and `app/src/lib/realtime/` for the Realtime client.
