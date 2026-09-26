// The two identity decisions in signup, kept pure so they can be tested
// without Deno or a database (src/lib/signupRules.test.js imports this file).
//
// Background: signUp() creates the auth login and signs the person in at once
// (email confirmations are off), then /register creates the public.users row.
// When /register refused — a taken username, most often — the client signed
// out but the login stayed, and that email could never sign up again. Both
// endpoints now act only on the identity PROVEN by the caller's session.

/**
 * Whose profile /register may create. Only the verified session's own. The
 * body may still carry an `id` (older clients sent one), but it can only ever
 * agree with the session — it is never trusted on its own. Before this, the id
 * came from the body with only the public key as authorisation, so any
 * login without a profile yet could be claimed by whoever knew its id.
 */
export function registerIdentity(
  { verifiedId, bodyId }: { verifiedId: string | null; bodyId: unknown }
): { ok: true; id: string } | { ok: false; status: number; error: string } {
  if (!verifiedId) {
    return { ok: false, status: 401, error: 'Sign-in session missing — please try signing up again.' }
  }
  if (bodyId !== undefined && bodyId !== null && bodyId !== '' && bodyId !== verifiedId) {
    return { ok: false, status: 403, error: 'That account does not belong to this session.' }
  }
  return { ok: true, id: verifiedId }
}

// How long after creation a login may still be abandoned. Signup calls it
// within seconds of a refused /register; the window only has to cover a slow
// phone, and keeping it short means this path can never reach an old account.
export const ABANDON_MAX_AGE_MS = 15 * 60 * 1000

/**
 * Whether abandon-signup may delete the caller's login. All three must hold:
 *   - no profile row: every finished account has one, so this can only ever
 *     remove a half-created signup, never a real account;
 *   - created recently: defence in depth, so even an old account that somehow
 *     lost its profile row is out of reach of this endpoint;
 *   - a creation time that parses: an unreadable one refuses, never allows.
 * The caller's identity itself comes from the verified session, not from here.
 */
export function abandonDecision(
  { profileExists, createdAt, now }: { profileExists: boolean; createdAt: unknown; now: number }
): { allowed: true } | { allowed: false; code: 'PROFILE_EXISTS' | 'TOO_OLD' | 'UNKNOWN_AGE' } {
  if (profileExists) return { allowed: false, code: 'PROFILE_EXISTS' }
  const created = typeof createdAt === 'string' ? Date.parse(createdAt) : Number.NaN
  if (!Number.isFinite(created)) return { allowed: false, code: 'UNKNOWN_AGE' }
  if (now - created > ABANDON_MAX_AGE_MS) return { allowed: false, code: 'TOO_OLD' }
  return { allowed: true }
}
