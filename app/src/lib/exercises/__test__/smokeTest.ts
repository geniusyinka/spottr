/**
 * Tiny smoke test for the analyzers — run with:
 *   npx tsx src/lib/exercises/__test__/smokeTest.ts
 *
 * Generates synthetic poses for a few squat reps and verifies the analyzer
 * counts them and (optionally) flags shallow depth.
 */
import { SquatAnalyzer } from '../squat';
import { PushUpAnalyzer } from '../pushup';
import type { KeypointName, Pose } from '../types';

function makePose(
  positions: Partial<Record<KeypointName, [number, number]>>,
  ts: number,
  score = 0.9,
): Pose {
  const keypoints: Pose['keypoints'] = {};
  for (const [name, xy] of Object.entries(positions) as [KeypointName, [number, number]][]) {
    keypoints[name] = { name, x: xy[0], y: xy[1], score };
  }
  return { keypoints, timestamp: ts };
}

// Synthesize a side-view squat: hip drops, knee moves forward (smaller x),
// producing a hip→knee→ankle angle that decreases with depth.
function squatPose(t: number, depth: number): Pose {
  const shoulderX = 0.55;
  const hipX = 0.55;
  const ankleX = 0.55;
  const kneeX = 0.55 - 0.18 * depth; // knee swings forward in 2D side view

  const shoulderY = 0.25 + 0.1 * depth;
  const hipY = 0.45 + 0.18 * depth;
  const kneeY = 0.65 + 0.05 * depth;
  const ankleY = 0.95;
  return makePose(
    {
      left_shoulder: [shoulderX, shoulderY],
      right_shoulder: [shoulderX, shoulderY + 0.01],
      left_hip: [hipX, hipY],
      right_hip: [hipX, hipY + 0.01],
      left_knee: [kneeX, kneeY],
      right_knee: [kneeX, kneeY + 0.01],
      left_ankle: [ankleX, ankleY],
      right_ankle: [ankleX, ankleY + 0.01],
    },
    t,
  );
}

function runSquatTest() {
  const a = new SquatAnalyzer();
  let t = 0;
  let totalEvents = 0;
  for (let rep = 0; rep < 3; rep++) {
    // descend
    for (let d = 0; d <= 1; d += 0.1) {
      const events = a.update(squatPose(t, d));
      totalEvents += events.length;
      t += 80;
    }
    // ascend
    for (let d = 1; d >= 0; d -= 0.1) {
      const events = a.update(squatPose(t, d));
      totalEvents += events.length;
      t += 80;
    }
  }
  const snap = a.snapshot();
  console.log('squat snapshot', snap, 'events', totalEvents);
  if (snap.reps !== 3) {
    console.error(`FAIL: expected 3 reps, got ${snap.reps}`);
    process.exitCode = 1;
  } else {
    console.log('PASS: squat counted 3 reps');
  }
}

function pushupPose(t: number, depth: number): Pose {
  // Person in plank — y values stay roughly horizontal across body.
  // Elbow y stays similar; what changes is elbow x relative to shoulder/wrist
  // to drive elbow angle. Simplification: vary wrist y so angle changes.
  const shoulderY = 0.5;
  const elbowY = 0.55 + 0.05 * depth;
  const wristY = 0.6;
  const hipY = 0.5;
  const ankleY = 0.5;
  return makePose(
    {
      left_shoulder: [0.4, shoulderY],
      right_shoulder: [0.4, shoulderY + 0.02],
      left_elbow: [0.45 + 0.05 * depth, elbowY],
      right_elbow: [0.45 + 0.05 * depth, elbowY + 0.02],
      left_wrist: [0.5, wristY],
      right_wrist: [0.5, wristY + 0.02],
      left_hip: [0.6, hipY],
      right_hip: [0.6, hipY + 0.02],
      left_ankle: [0.85, ankleY],
      right_ankle: [0.85, ankleY + 0.02],
    },
    t,
  );
}

function runPushupTest() {
  const a = new PushUpAnalyzer();
  let t = 0;
  for (let rep = 0; rep < 2; rep++) {
    for (let d = 0; d <= 1; d += 0.1) {
      a.update(pushupPose(t, d));
      t += 80;
    }
    for (let d = 1; d >= 0; d -= 0.1) {
      a.update(pushupPose(t, d));
      t += 80;
    }
  }
  const snap = a.snapshot();
  console.log('pushup snapshot', snap);
}

runSquatTest();
runPushupTest();
