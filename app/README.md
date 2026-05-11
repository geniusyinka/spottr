# spottr-app

Expo + TypeScript mobile app. Camera + on-device pose estimation +
WebRTC connection to OpenAI Realtime.

## Requirements

- Node 20+
- iOS: Xcode 15+, CocoaPods, an iPhone (simulator can't access the camera).
- Android: Android Studio, an Android device or emulator with camera support.
- A running `spottr-server` reachable from your phone on the LAN.

## Setup

```bash
cp .env.example .env
# set EXPO_PUBLIC_BACKEND_URL to your machine's LAN IP, e.g. http://192.168.1.10:8787
npm install
```

Spottr uses `react-native-webrtc` and TF.js native modules, so it needs a
**dev client build** — Expo Go won't work.

```bash
npx expo prebuild           # one-time: generates ios/ and android/
npx expo run:ios            # or: npx expo run:android
```

After the dev client is installed on your phone, start Metro with:

```bash
npm start
```

## Architecture

```
app/
├── App.tsx                       # navigation root
├── index.ts
└── src/
    ├── config.ts
    ├── theme.ts
    ├── screens/
    │   ├── HomeScreen.tsx
    │   ├── ExerciseSelectScreen.tsx
    │   ├── WorkoutScreen.tsx     # camera + analyzer + realtime
    │   └── SummaryScreen.tsx
    ├── components/
    │   ├── StatsHUD.tsx
    │   └── EndSetButton.tsx
    ├── lib/
    │   ├── exercises/            # squat + push-up rep + form analyzers
    │   ├── pose/                 # MoveNet + camera tensor stream
    │   ├── realtime/             # OpenAI Realtime WebRTC client
    │   └── summary.ts            # post-set summary builder
    └── state/
        └── sessionStore.ts       # zustand
```

## Privacy

- Frames are only used in-memory for pose estimation. They are never written
  to disk or uploaded.
- Only structured movement events (rep counts, form flags) are pushed over
  the Realtime data channel, not images.
- The mic stream is uploaded to OpenAI Realtime over WebRTC for the voice
  coach. Disable the mic anytime via `realtimeRef.current.setMicEnabled(false)`.

## Known limitations (MVP)

- TF.js MoveNet on a phone is ~10–15 fps; reps in extremely fast tempo may be
  miscounted.
- Single-person, front-facing detection only.
- No persistent history yet — summaries live for the lifetime of the screen.
