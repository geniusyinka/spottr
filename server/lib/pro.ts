import type { VercelRequest } from '@vercel/node';

/**
 * Server-side "Spottr Pro" check for every endpoint that costs money per call.
 *
 * The app sends its RevenueCat app user ID in `X-RC-App-User-Id`; we ask
 * RevenueCat whether that user holds the entitlement. Answers are cached per
 * warm instance for a few minutes — a set makes a dozen calls, and RevenueCat
 * doesn't need to hear about each one.
 *
 * Uses RevenueCat API v2, so REVENUECAT_SECRET_KEY must be a v2 secret key
 * with the customer_information:customers:read permission (read-only).
 *
 * Rollout: for endpoints that existed before the check (Realtime, vision),
 * enforcement switches on when REVENUECAT_SECRET_KEY is set, so deploying
 * doesn't break them before the key is added. New paid endpoints pass
 * `failClosed` and refuse everything until the key is there.
 */

const PROJECT_ID = process.env.REVENUECAT_PROJECT_ID ?? 'proj21c01bbe';
/** The "Spottr Pro" entitlement's v2 id (v2 reports entitlements by id, not name). */
const ENTITLEMENT_ID = process.env.REVENUECAT_ENTITLEMENT_ID ?? 'entl68bd2d4127';
const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map<string, { pro: boolean; checkedAt: number }>();

export type ProCheck = { ok: true } | { ok: false; status: number; error: string };

export async function requirePro(req: VercelRequest, options: { failClosed?: boolean } = {}): Promise<ProCheck> {
  const secret = process.env.REVENUECAT_SECRET_KEY;
  if (!secret) {
    if (options.failClosed) {
      return { ok: false, status: 503, error: 'entitlement check not configured' };
    }
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
    `https://api.revenuecat.com/v2/projects/${PROJECT_ID}/customers/${encodeURIComponent(userId)}/active_entitlements`,
    { headers: { Authorization: `Bearer ${secret}` } },
  );
  if (upstream.status === 404) return false; // never purchased, so RevenueCat has no customer
  if (!upstream.ok) throw new Error(`RevenueCat ${upstream.status}`);
  const body = (await upstream.json()) as {
    items?: Array<{ entitlement_id?: string; expires_at?: number | null }>;
  };
  // Active entitlements only; expires_at is ms since epoch, null for lifetime.
  return (body.items ?? []).some(
    (item) => item.entitlement_id === ENTITLEMENT_ID && (item.expires_at == null || item.expires_at > Date.now()),
  );
}
