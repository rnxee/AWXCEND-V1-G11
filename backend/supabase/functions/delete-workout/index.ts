import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// A player deletes one of their own workouts, and the XP, path XP, attribute points, rank and
// strength record it gave are taken back in the same transaction (delete_workout_log).
//
//   POST { workout_log_id }
//
// Manual workouts only, within 24 hours, never a mission or dungeon set: the database function
// enforces all of it and explains a refusal in the player's own words.

const RL_MAX = 30
const RL_WINDOW_SECONDS = 300

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  // Shares log-workout's bucket, so log + delete loops can't run faster than logging alone.
  if (!(await checkRateLimit(user.id, 'log_workout', 40, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)
  if (!(await checkRateLimit(user.id, 'delete_workout', RL_MAX, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)

  const body = await req.json().catch(() => ({}))
  if (!isUuid(body.workout_log_id)) return json({ success: false, error: 'A valid workout_log_id is required.' }, 400)

  const { data, error } = await getAdminClient().rpc('delete_workout_log', {
    p_user_id: user.id, p_log_id: body.workout_log_id
  })
  if (error) {
    const status = /LOG_NOT_FOUND/.test(error.message) ? 404 : /NOT_DELETABLE/.test(error.message) ? 409 : 500
    return json({ success: false, error: status === 500 ? 'Could not delete the workout.' : playerMessage(error.message) }, status)
  }
  return json(data)
})
