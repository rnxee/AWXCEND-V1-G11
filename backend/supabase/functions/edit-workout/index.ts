import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// Correct the sets, reps, weight or time of a workout you logged by hand. One database transaction
// (edit_workout_log) takes the old workout back and logs the new numbers, so XP, rank and the strength
// record always match. Same rules as deleting one: manual, under 24 hours, not a mission or dungeon set.
//
//   POST { workout_log_id, sets?, reps?, weight_kg?, duration_seconds? }

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

/** A number, null when left out, or undefined when present but not a number. */
function num(v: unknown, whole: boolean): number | null | undefined {
  if (v === undefined || v === null || v === '') return null
  const n = Number(v)
  if (!Number.isFinite(n) || (whole && !Number.isInteger(n))) return undefined
  return n
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  // Shares log-workout's bucket, so edit loops can't run faster than logging alone.
  if (!(await checkRateLimit(user.id, 'log_workout', 40, 300))) return rateLimitResponse(corsHeaders)

  const body = await req.json().catch(() => ({}))
  if (!isUuid(body.workout_log_id)) return json({ success: false, error: 'A valid workout_log_id is required.' }, 400)
  const sets = num(body.sets, true), reps = num(body.reps, true)
  const weight = num(body.weight_kg, false), duration = num(body.duration_seconds, true)
  if ([sets, reps, weight, duration].includes(undefined)) {
    return json({ success: false, error: 'Sets, reps, weight and time must be numbers.' }, 400)
  }

  // The database checks every range for the exercise's own kind (reps or time) and explains a refusal.
  const { data, error } = await getAdminClient().rpc('edit_workout_log', {
    p_user_id: user.id, p_log_id: body.workout_log_id,
    p_sets: sets, p_reps: reps, p_weight_kg: weight, p_duration_seconds: duration
  })
  if (error) {
    const known = /^(LOG_NOT_FOUND|NOT_DELETABLE|INVALID_[A-Z_]+):/.test(error.message)
    const status = /^LOG_NOT_FOUND/.test(error.message) ? 404 : /^NOT_DELETABLE/.test(error.message) ? 409 : known ? 400 : 500
    return json({ success: false, error: known ? playerMessage(error.message).replace('deleted', 'edited') : 'Could not edit the workout.' }, status)
  }
  return json(data)
})
