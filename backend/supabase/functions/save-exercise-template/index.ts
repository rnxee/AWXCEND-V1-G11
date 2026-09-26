import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { consentRequiredResponse } from '../_shared/consent.ts'

// Upserts the caller's reference rep for one exercise. Called whenever a
// tracker finishes calibration, including a deliberate re-record — the unique
// (user_id, exercise) constraint means the newest reference always replaces the
// old one rather than accumulating.

// Bounds are generous but finite. Templates are resampled to TEMPLATE_LENGTH
// (30) by every tracker, and the widest feature vector in the app is jumping
// jacks' 16 — these caps exist to reject malformed or hostile payloads, not to
// constrain legitimate ones.
const MAX_FRAMES = 200
const MAX_DIMENSIONS = 64
const MAX_EXERCISE_LEN = 64
const COORD_LIMIT = 1000

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

  if (!(await checkRateLimit(user.id, 'save_exercise_template', 30, 600))) {
    return rateLimitResponse(corsHeaders)
  }

  // Saving joint coordinates requires the current camera notice.
  const consentBlock = await consentRequiredResponse(user.id, 'camera', corsHeaders)
  if (consentBlock) return consentBlock

  const body = await req.json().catch(() => ({}))
  const exercise = typeof body.exercise === 'string' ? body.exercise.trim() : ''
  const frames = body.frames

  const errors: string[] = []
  if (!exercise) errors.push('exercise is required')
  if (exercise.length > MAX_EXERCISE_LEN) errors.push(`exercise must be ${MAX_EXERCISE_LEN} characters or fewer`)

  if (!Array.isArray(frames) || frames.length === 0) {
    errors.push('frames must be a non-empty array')
  } else if (frames.length > MAX_FRAMES) {
    errors.push(`frames must contain at most ${MAX_FRAMES} entries`)
  }

  let dimensions = 0
  if (errors.length === 0) {
    // Every frame must be the same width — a ragged template would produce
    // silently meaningless DTW distances rather than an error, since the
    // distance function just sums over whatever it's given.
    dimensions = Array.isArray(frames[0]) ? frames[0].length : -1
    if (dimensions <= 0 || dimensions > MAX_DIMENSIONS) {
      errors.push(`each frame must have between 1 and ${MAX_DIMENSIONS} values`)
    } else {
      for (let i = 0; i < frames.length; i++) {
        const frame = frames[i]
        if (!Array.isArray(frame) || frame.length !== dimensions) {
          errors.push(`frames[${i}] must be an array of ${dimensions} numbers`)
          break
        }
        // Coordinates are hip-centred and torso-scaled, so legitimate values
        // sit within a couple of torso lengths of the origin. Anything wildly
        // outside that is corrupt, and NaN/Infinity would poison every
        // subsequent DTW comparison against this template.
        if (!frame.every((v: unknown) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= COORD_LIMIT)) {
          errors.push(`frames[${i}] contains a non-finite or out-of-range value`)
          break
        }
      }
    }
  }

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()
  const { error } = await admin
    .from('user_exercise_templates')
    .upsert({
      user_id: user.id,
      exercise,
      frames,
      dimensions,
      frame_count: frames.length,
      updated_at: new Date().toISOString()
    }, { onConflict: 'user_id,exercise' })

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, exercise, dimensions, frameCount: frames.length }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
