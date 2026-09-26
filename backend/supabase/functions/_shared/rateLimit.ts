import { getAdminClient } from './supabaseAdmin.ts'

// Per-user request rate limiting, backed by the `rate_limits` table and the
// `check_rate_limit` RPC (see the rate-limiting migration). Edge function
// instances are stateless and distributed, so the counter has to live in the
// database — an in-memory counter would reset on every cold start and never be
// shared across instances. The RPC does the check-and-increment atomically in
// one statement so concurrent requests can't race past the limit.

/**
 * Returns true if the request is ALLOWED (under the limit), false if it should
 * be rejected with 429.
 *
 * Fails OPEN: if the rate-limit infrastructure itself errors (RPC missing, DB
 * hiccup), the request is allowed and the error is logged. A rate-limiter
 * outage must never take the whole app down, and this is what lets the
 * functions be deployed before the migration lands — until the RPC exists,
 * every call simply passes through.
 */
export async function checkRateLimit(
  userId: string,
  action: string,
  max: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const admin = getAdminClient()
    const { data, error } = await admin.rpc('check_rate_limit', {
      p_user_id: userId,
      p_action: action,
      p_max: max,
      p_window_seconds: windowSeconds,
    })
    if (error) {
      console.error(`[rate-limit] check failed for ${action}:`, error.message)
      return true
    }
    return data === true
  } catch (e) {
    console.error(`[rate-limit] check threw for ${action}:`, (e as Error).message)
    return true
  }
}

/** Standard 429 response body, shaped like every other function's error. */
export function rateLimitResponse(
  corsHeaders: Record<string, string>,
  message = 'Too many requests — please slow down and try again shortly.',
): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    status: 429,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
