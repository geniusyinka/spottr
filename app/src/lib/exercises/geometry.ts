import type { Keypoint } from './types';

/** Angle ABC in degrees (joint at B). Returns NaN if any point is missing. */
export function angleDeg(a?: Keypoint, b?: Keypoint, c?: Keypoint): number {
  if (!a || !b || !c) return NaN;
  const v1x = a.x - b.x;
  const v1y = a.y - b.y;
  const v2x = c.x - b.x;
  const v2y = c.y - b.y;
  const dot = v1x * v2x + v1y * v2y;
  const m1 = Math.hypot(v1x, v1y);
  const m2 = Math.hypot(v2x, v2y);
  if (m1 === 0 || m2 === 0) return NaN;
  const cos = Math.max(-1, Math.min(1, dot / (m1 * m2)));
  return (Math.acos(cos) * 180) / Math.PI;
}

export function midpoint(a?: Keypoint, b?: Keypoint): { x: number; y: number } | null {
  if (!a || !b) return null;
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

/** Average confidence of provided keypoints (NaN if none). */
export function avgScore(...kps: Array<Keypoint | undefined>): number {
  const xs = kps.filter((k): k is Keypoint => Boolean(k));
  if (xs.length === 0) return NaN;
  return xs.reduce((s, k) => s + k.score, 0) / xs.length;
}
