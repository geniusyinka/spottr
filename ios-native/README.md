# Spottr — Native iOS

SwiftUI port of the React Native Spottr app. Same backend (`server/`).
Adds working pose detection (Apple's Vision framework) since we no longer
depend on TF.js + expo-gl.

## What's different vs the RN app

- **Pose detection works.** `VNDetectHumanBodyPoseRequest` runs on every
  camera frame via `AVCaptureSession`; the squat/push-up analyzers from the
  TS app are ported to Swift one-to-one.
- **No Metro / dev client.** Build via Xcode + `xcodegen`.
- **Audio session is configured directly** (`.playAndRecord`, `.voiceChat`,
  `defaultToSpeaker`) — coach voice plays through the speaker even when
  AirPods aren't connected.
- **WebRTC native** via SPM (`stasel/WebRTC`), wired to the same
  `/api/realtime/session` endpoint on the Node backend.

## Build

```bash
cd ios-native
xcodegen generate
open Spottr.xcodeproj
```

The xcodegen spec auto-creates `Spottr.xcodeproj` + the WebRTC SPM dep.

To build + install on your device from CLI:

```bash
xcodebuild \
  -project Spottr.xcodeproj \
  -scheme Spottr \
  -configuration Debug \
  -destination "id=00008140-00123D2902BB001C" \
  -allowProvisioningUpdates \
  build

xcrun devicectl device install app \
  --device D66F32F8-6D31-56EB-8730-041B7E013052 \
  ~/Library/Developer/Xcode/DerivedData/Spottr-*/Build/Products/Debug-iphoneos/Spottr.app
```

## Backend

Same as the RN app:

```bash
cd ../server
npm run dev
```

The app uses `http://localhost:8787` on the simulator and falls back to
`http://192.168.18.15:8787` on device. Override at build time by setting
`SpottrBackendURL` in `Info.plist`.

## File layout

```
ios-native/
├── project.yml
└── Spottr/
    ├── SpottrApp.swift            # @main + navigation
    ├── Theme.swift
    ├── Info.plist
    ├── Spottr.entitlements
    ├── Models/
    │   ├── ExerciseTypes.swift    # ExerciseId, FormIssue, RepCompleted
    │   └── PoseTypes.swift        # KeypointName, Pose
    ├── Analyzers/
    │   ├── ExerciseAnalyzer.swift # protocol + factory
    │   ├── Geometry.swift
    │   ├── SquatAnalyzer.swift
    │   └── PushupAnalyzer.swift
    ├── Pose/
    │   ├── CameraSession.swift    # AVCaptureSession
    │   ├── PoseDetector.swift     # VNDetectHumanBodyPoseRequest
    │   └── VisualFrameSampler.swift # compressed snapshots for semantic vision
    ├── Realtime/
    │   ├── BackendClient.swift    # POST /api/realtime/session
    │   ├── CoachEvent.swift       # event encoding + envelope helpers
    │   └── RealtimeClient.swift   # RTCPeerConnection + data channel
    ├── State/
    │   └── SessionState.swift     # ObservableObject, SetSummary
    └── Views/
        ├── HomeView.swift
        ├── ExerciseSelectView.swift
        ├── CameraPreviewView.swift
        ├── WorkoutView.swift
        └── SummaryView.swift
```

## Privacy

- Frames are processed in-memory by Vision and immediately discarded for pose tracking.
- Every few seconds, a compressed JPEG snapshot is sent to the backend for semantic vision. The backend returns structured visual facts; snapshots are not stored by this app.
- Structured movement events and structured visual facts flow over the Realtime data channel.
- The mic stream goes to OpenAI Realtime over WebRTC for the voice coach;
  toggle off via `realtime.setMicEnabled(false)` if you want to mute.
