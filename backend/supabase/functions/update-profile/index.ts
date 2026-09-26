import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import {
  isSpecialization,
  specializationList,
  specializationSwitchState,
  SPECIALIZATION_LOCK_DAYS
} from '../_shared/specializations.ts'

const MAX_USERNAME_LENGTH = 30
const MAX_BIO_LENGTH = 300
const ALLOWED_SEX = ['male', 'female']
const ALLOWED_GOALS = ['bulk', 'cut', 'maintain']

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

  if (!(await checkRateLimit(user.id, 'update_profile', 20, 600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const username = typeof body.username === 'string' ? body.username.trim() : ''
  const bio = typeof body.bio === 'string' ? body.bio.trim() : ''

  // Optional, same as bio — omitted or blank clears the field back to null so
  // someone who set a value can also unset it (e.g. after a bad entry).
  const weightKg = body.weight_kg === '' || body.weight_kg === undefined || body.weight_kg === null
    ? null : Number(body.weight_kg)
  const heightCm = body.height_cm === '' || body.height_cm === undefined || body.height_cm === null
    ? null : Number(body.height_cm)
  const sex = typeof body.sex === 'string' && body.sex.trim() ? body.sex.trim().toLowerCase() : null
  const age = body.age === '' || body.age === undefined || body.age === null ? null : Number(body.age)
  const goal = typeof body.goal === 'string' && body.goal.trim() ? body.goal.trim().toLowerCase() : null
  const focusType = typeof body.focus_type === 'string' && body.focus_type.trim() ? body.focus_type.trim().toLowerCase() : null

  const errors: string[] = []
  if (!username) errors.push('Username is required')
  if (username.length > MAX_USERNAME_LENGTH) errors.push(`Username must be ${MAX_USERNAME_LENGTH} characters or fewer`)
  if (bio.length > MAX_BIO_LENGTH) errors.push(`Bio must be ${MAX_BIO_LENGTH} characters or fewer`)
  if (weightKg !== null && (!Number.isFinite(weightKg) || weightKg <= 0 || weightKg >= 500)) errors.push('Weight must be between 0 and 500 kg')
  if (heightCm !== null && (!Number.isFinite(heightCm) || heightCm <= 0 || heightCm >= 300)) errors.push('Height must be between 0 and 300 cm')
  if (sex !== null && !ALLOWED_SEX.includes(sex)) errors.push(`Sex must be one of: ${ALLOWED_SEX.join(', ')}`)
  if (age !== null && (!Number.isInteger(age) || age <= 0 || age >= 120)) errors.push('Age must be a whole number between 0 and 120')
  if (goal !== null && !ALLOWED_GOALS.includes(goal)) errors.push(`Goal must be one of: ${ALLOWED_GOALS.join(', ')}`)
  if (focusType !== null && !isSpecialization(focusType)) errors.push(`Focus path must be one of: ${specializationList()}`)

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // focus_type is NOT NULL with a default at signup — unlike the other
  // optional fields here, omitting it from a request must leave the
  // existing value alone rather than null it out.
  const updates: Record<string, unknown> = { username, bio, weight_kg: weightKg, height_cm: heightCm, sex, age, goal }

  if (focusType !== null) {
    const { data: current } = await admin
      .from('users')
      .select('focus_type, specialization_started_at')
      .eq('id', user.id)
      .maybeSingle()

    const isActualSwitch = current && current.focus_type !== focusType

    if (isActualSwitch) {
      // A path is a training commitment, not a per-workout XP optimisation:
      // without this lock a user could switch to whichever specialization
      // most favours today's exercise, collect the affinity bonus, and switch
      // back tomorrow.
      const { canSwitch, daysRemaining } = specializationSwitchState(
        current.specialization_started_at
      )

      if (!canSwitch) {
        return new Response(JSON.stringify({
          success: false,
          errors: [`You can change your path in ${daysRemaining} day${daysRemaining === 1 ? '' : 's'}. Each path is locked in for ${SPECIALIZATION_LOCK_DAYS} days.`]
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      updates.focus_type = focusType
      updates.specialization_started_at = new Date().toISOString()

      // Rank belongs to the path being switched TO, computed from whatever XP
      // the user has already banked on that path (0 for a path never trained).
      // Without this the user would keep displaying the old path's rank name.
      const { data: incomingXp } = await admin
        .from('user_specialization_xp')
        .select('xp')
        .eq('user_id', user.id)
        .eq('focus_type', focusType)
        .maybeSingle()

      const { data: resolved } = await admin
        .rpc('resolve_specialization_rank', {
          p_focus_type: focusType,
          p_xp: incomingXp?.xp ?? 0
        })
        .maybeSingle()

      if (resolved) {
        updates.rank = resolved.rank_name
        updates.rank_sub_index = resolved.sub_rank
      }
    } else {
      updates.focus_type = focusType
    }
  }

  const { data, error } = await admin
    .from('users')
    .update(updates)
    .eq('id', user.id)
    .select()

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, profile: data[0] }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
