import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'

// XP/rank/attribute farming guard. A real session logs a set every few tens of
// seconds at most; 40 in 5 minutes is far above any human cadence but still
// throttles a script looping the endpoint to inflate progress. Per-request
// value caps (sets/reps/weight) already exist below — this caps the RATE.
const RL_MAX = 40
const RL_WINDOW_SECONDS = 300

const ALLOWED_SOURCES = ['camera', 'manual']
const MAX_SETS = 20
const MAX_REPS = 300
const MAX_WEIGHT_KG = 500
const MAX_DURATION_SECONDS = 21600  // 6h
const MAX_DISTANCE_M = 200000       // 200km

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) {
    return new Response(JSON.stringify({ success: false, error: authError }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  if (!(await checkRateLimit(user.id, 'log_workout', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const exercise = typeof body.exercise === 'string' ? body.exercise.trim().toLowerCase() : ''
  const sets = Number(body.sets)
  const reps = Number(body.reps)
  const source = typeof body.workout_source === 'string' ? body.workout_source.trim().toLowerCase() : ''
  const rawQuality = body.rep_quality_score
  // Optional — bodyweight movements skip this and keep the original
  // reps-only XP formula (see the RPC), no behavior change for them.
  const weightProvided = body.weight_kg !== undefined && body.weight_kg !== null && body.weight_kg !== ''
  const weightKg = weightProvided ? Number(body.weight_kg) : null

  // Cardio inputs. Their presence is what switches this endpoint out of
  // sets/reps mode — the authoritative decision is still the exercise's
  // metric_type inside the RPC, which re-validates everything; this only
  // decides which shape of request to accept here.
  const durationProvided = body.duration_seconds !== undefined && body.duration_seconds !== null && body.duration_seconds !== ''
  const durationSeconds = durationProvided ? Number(body.duration_seconds) : null
  const distanceProvided = body.distance_m !== undefined && body.distance_m !== null && body.distance_m !== ''
  const distanceM = distanceProvided ? Number(body.distance_m) : null
  // Reps take precedence over duration when both are sent. A timed set of
  // jumping jacks is still rep-counted — the duration is supplementary
  // metadata, not a switch into distance/time scoring. Only an entry with NO
  // reps at all is treated as pure cardio.
  const repsProvided = body.reps !== undefined && body.reps !== null && body.reps !== ''
  const isCardio = !repsProvided && (durationProvided || distanceProvided)

  const errors: string[] = []
  if (!source || !ALLOWED_SOURCES.includes(source)) errors.push(`workout_source must be one of: ${ALLOWED_SOURCES.join(', ')}`)
  if (!exercise) errors.push('exercise is required')

  if (isCardio) {
    // sets/reps are meaningless for time/distance work and stay null.
    if (!Number.isFinite(durationSeconds!) || durationSeconds! < 1 || durationSeconds! > MAX_DURATION_SECONDS) {
      errors.push(`duration_seconds must be between 1 and ${MAX_DURATION_SECONDS}`)
    }
    if (distanceProvided && (!Number.isFinite(distanceM!) || distanceM! < 0 || distanceM! > MAX_DISTANCE_M)) {
      errors.push(`distance_m must be between 0 and ${MAX_DISTANCE_M}`)
    }
  } else {
    if (!Number.isFinite(sets) || sets < 1 || sets > MAX_SETS) errors.push(`sets must be between 1 and ${MAX_SETS}`)
    if (!Number.isFinite(reps) || reps < 1 || reps > MAX_REPS) errors.push(`reps must be between 1 and ${MAX_REPS}`)
    // Rep-counted work may still carry a duration (e.g. a timed set of
    // jumping jacks). Bounded, but optional.
    if (durationProvided && (!Number.isFinite(durationSeconds!) || durationSeconds! < 0 || durationSeconds! > MAX_DURATION_SECONDS)) {
      errors.push(`duration_seconds must be between 0 and ${MAX_DURATION_SECONDS}`)
    }
  }

  if (weightProvided && (!Number.isFinite(weightKg!) || weightKg! < 0 || weightKg! > MAX_WEIGHT_KG)) {
    errors.push(`weight_kg must be between 0 and ${MAX_WEIGHT_KG}`)
  }

  const qualityProvided = rawQuality !== undefined && rawQuality !== null
  const qualityScore = qualityProvided ? Number(rawQuality) : null
  // Cardio has no per-rep form score, so the camera requirement only applies
  // to rep-counted camera work.
  if (source === 'camera' && !isCardio) {
    if (!qualityProvided || !Number.isFinite(qualityScore!) || qualityScore! < 0 || qualityScore! > 1) {
      errors.push('rep_quality_score must be between 0.0 and 1.0 for camera workouts')
    }
  }

  // GPS routes are not stored (Phase 4A privacy hardening): only distance and
  // duration are kept. A `route` field from an older client is ignored.

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()
  const { data, error } = await admin.rpc('log_workout_and_progress', {
    p_user_id: user.id,
    p_exercise: exercise,
    p_sets: isCardio ? null : sets,
    p_reps: isCardio ? null : reps,
    p_rep_quality_score: source === 'camera' && !isCardio ? qualityScore : null,
    p_workout_source: source,
    p_weight_kg: weightKg,
    p_duration_seconds: durationSeconds,
    p_distance_m: distanceM
  })

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
