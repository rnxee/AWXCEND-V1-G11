import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// Every mission action a player can take, grouped in one function so the
// deploy surface stays small:
//
//   start            begin (or replay) a mission
//   objective_start  stamp the moment tracking goes live for the current
//                    objective — the baseline for the plausibility check
//   submit           hand in a finished set
//   abandon          give up the current attempt
//
// Nothing here decides an outcome. Damage, clears, rewards and deadlines are
// all computed inside the database functions, which take the user id from
// the verified token below and never from the request body.

// A submit logs a real workout inside the database, which means it would
// otherwise sidestep log-workout's farming guard entirely. It shares that
// guard's bucket and limits instead, so routing sets through a mission buys a
// script no extra headroom.
const SUBMIT_RL = { action: 'log_workout', max: 40, windowSeconds: 300 }
const OTHER_RL = { action: 'mission_attempt', max: 60, windowSeconds: 300 }

const ALLOWED_SOURCES = ['camera', 'manual']
const MAX_ACHIEVED = 21600 // six hours of hold, or far more reps than anyone does
const MAX_WEIGHT_KG = 500

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

// Database errors arrive as "CODE: human sentence". The code is for logs;
// the sentence is written to be shown to the player.
function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const body = await req.json().catch(() => ({}))
  const action = typeof body.action === 'string' ? body.action : ''

  const rl = action === 'submit' ? SUBMIT_RL : OTHER_RL
  if (!(await checkRateLimit(user.id, rl.action, rl.max, rl.windowSeconds))) {
    return rateLimitResponse(corsHeaders)
  }

  const admin = getAdminClient()
  let rpc: { name: string; args: Record<string, unknown> }

  if (action === 'start') {
    if (!isUuid(body.mission_id)) return json({ success: false, error: 'A valid mission_id is required.' }, 400)
    rpc = { name: 'start_mission_attempt', args: { p_user_id: user.id, p_mission_id: body.mission_id } }

  } else if (action === 'objective_start' || action === 'abandon') {
    if (!isUuid(body.attempt_id)) return json({ success: false, error: 'A valid attempt_id is required.' }, 400)
    rpc = {
      name: action === 'abandon' ? 'abandon_mission_attempt' : 'start_mission_objective',
      args: { p_user_id: user.id, p_attempt_id: body.attempt_id }
    }

  } else if (action === 'submit') {
    if (!isUuid(body.attempt_id)) return json({ success: false, error: 'A valid attempt_id is required.' }, 400)

    const achieved = Number(body.achieved)
    if (!Number.isFinite(achieved) || achieved <= 0 || achieved > MAX_ACHIEVED) {
      return json({ success: false, error: `achieved must be between 0 and ${MAX_ACHIEVED}.` }, 400)
    }

    const source = typeof body.workout_source === 'string' ? body.workout_source : 'camera'
    if (!ALLOWED_SOURCES.includes(source)) {
      return json({ success: false, error: `workout_source must be one of: ${ALLOWED_SOURCES.join(', ')}.` }, 400)
    }

    const qualityProvided = body.form_quality !== undefined && body.form_quality !== null
    const quality = qualityProvided ? Number(body.form_quality) : null
    if (qualityProvided && (!Number.isFinite(quality!) || quality! < 0 || quality! > 1)) {
      return json({ success: false, error: 'form_quality must be between 0 and 1.' }, 400)
    }

    const weightProvided = body.weight_kg !== undefined && body.weight_kg !== null && body.weight_kg !== ''
    const weightKg = weightProvided ? Number(body.weight_kg) : null
    if (weightProvided && (!Number.isFinite(weightKg!) || weightKg! < 0 || weightKg! > MAX_WEIGHT_KG)) {
      return json({ success: false, error: `weight_kg must be between 0 and ${MAX_WEIGHT_KG}.` }, 400)
    }

    rpc = {
      name: 'submit_mission_objective',
      args: {
        p_user_id: user.id,
        p_attempt_id: body.attempt_id,
        p_achieved: achieved,
        p_form_quality: quality,
        p_workout_source: source,
        p_weight_kg: weightKg
      }
    }

  } else {
    return json({ success: false, error: 'action must be one of: start, objective_start, submit, abandon.' }, 400)
  }

  const { data, error } = await admin.rpc(rpc.name, rpc.args)
  if (error) return json({ success: false, error: playerMessage(error.message) }, 400)

  return json(data, 200)
})
