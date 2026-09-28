import type { VercelRequest } from '@vercel/node';

/**
 * Server-side "Spottr Pro" check for every endpoint that costs money per call.
 *
 * The app sends its RevenueCat app user ID in `X-RC-App-User-Id`; we ask
 * RevenueCat whether that user holds the entitlement. Answers are cached per
 * warm instance for a few minutes — a set makes a dozen calls, and RevenueCat
 * doesn't need to hear about each one.
 *
 * Rollout: enforcement switches on when REVENUECAT_SECRET_KEY is set in the
 * environment. Until then every request is allowed (with a warning), so
 * deploying this doesn't break the Realtime coach before the key is added.
 */

const ENTITLEMENT = process.env.REVENUECAT_ENTITLEMENT ?? 'Spottr Pro';
const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map<string, { pro: boolean; checkedAt: number }>();

export type ProCheck = { ok: true } | { ok: false; status: number; error: string };

export async function requirePro(req: VercelRequest): Promise<ProCheck> {
  const secret = process.env.REVENUECAT_SECRET_KEY;
  if (!secret) {
    console.warn('REVENUECAT_SECRET_KEY not set — Pro check skipped');
    return { ok: true };
  }

  const header = req.headers['x-rc-app-user-id'];
  const userId = (Array.isArray(header) ? header[0] : header)?.trim();
  if (!userId || userId.length > 200) {
    return { ok: false, status: 401, error: 'missing app user id' };
  }

  const cached = cache.get(userId);
  if (cached && Date.now() - cached.checkedAt < CACHE_TTL_MS) {
    return cached.pro ? { ok: true } : { ok: false, status: 403, error: 'Spottr Pro required' };
  }

  let pro: boolean;
  try {
    pro = await hasEntitlement(userId, secret);
  } catch (err) {
    // RevenueCat down: don't lock paying users out of a set in progress if
    // we've seen them as Pro recently; otherwise fail closed.
    if (cached?.pro) return { ok: true };
    console.error('RevenueCat check failed', err);
    return { ok: false, status: 503, error: 'entitlement check unavailable' };
  }
  cache.set(userId, { pro, checkedAt: Date.now() });
  return pro ? { ok: true } : { ok: false, status: 403, error: 'Spottr Pro required' };
}

async function hasEntitlement(userId: string, secret: string): Promise<boolean> {
  const upstream = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    { headers: { Authorization: `Bearer ${secret}` } },
  );
  if (upstream.status === 404) return false;
  if (!upstream.ok) throw new Error(`RevenueCat ${upstream.status}`);
  const body = (await upstream.json()) as {
    subscriber?: { entitlements?: Record<string, { expires_date?: string | null }> };
  };
  const entitlement = body.subscriber?.entitlements?.[ENTITLEMENT];
  if (!entitlement) return false;
  // Lifetime purchases have no expiry.
  return entitlement.expires_date == null || Date.parse(entitlement.expires_date) > Date.now();
}
