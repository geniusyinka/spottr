import type { Pose } from '../exercises/types';

/**
 * Stubbed pose detector. The real MoveNet pipeline depended on
 * `@tensorflow/tfjs-react-native` + `expo-gl`, which does not compile against
 * Xcode 26's libc++. For the simulator-friendly MVP build, we no-op here and
 * gate live pose-driven rep counting in WorkoutScreen behind a flag.
 *
 * Re-enable: install `@tensorflow/tfjs`, `@tensorflow/tfjs-react-native`,
 * `@tensorflow-models/pose-detection`, and `expo-gl` (≥ a build patched for
 * recent Xcode), then restore this module.
 */
export const POSE_DETECTOR_AVAILABLE = false;

export async function getPoseDetector(): Promise<null> {
  return null;
}

export async function estimatePose(
  _input: unknown,
  _width: number,
  _height: number,
): Promise<Pose | null> {
  return null;
}

export async function disposePoseDetector(): Promise<void> {
  // no-op
}
