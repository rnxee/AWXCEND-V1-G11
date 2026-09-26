import { corsHeaders } from '../_shared/cors.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { registerIdentity } from '../_shared/signupRules.ts'
import {
  DEFAULT_SPECIALIZATION,
  isSpecialization,
  specializationList
} from '../_shared/specializations.ts'

const ALLOWED_SEX = ['male', 'female']
const ALLOWED_GOALS = ['bulk', 'cut', 'maintain']

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // signUp() signs the person in immediately (email confirmations are off),
  // so the client calls this with the NEW user's session. The profile is
  // created for that verified user only; a body id, if sent, must match it.
  const { user: sessionUser } = await getVerifiedUser(req)
  const body = await req.json().catch(() => ({}))
  const identity = registerIdentity({ verifiedId: sessionUser?.id ?? null, bodyId: body.id })
  if (!identity.ok) {
    return new Response(JSON.stringify({ success: false, error: identity.error }), {
      status: identity.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  const id = identity.id
  const username = typeof body.username === 'string' ? body.username.trim() : ''
  const focusType = typeof body.focus_type === 'string' ? body.focus_type.trim().toLowerCase() : DEFAULT_SPECIALIZATION

  // Optional — signup can be completed without them, same as before this field
  // existed, so an omitted or blank value just leaves the column null.
  const weightKg = body.weight_kg === '' || body.weight_kg === undefined || body.weight_kg === null
    ? null : Number(body.weight_kg)
  const heightCm = body.height_cm === '' || body.height_cm === undefined || body.height_cm === null
    ? null : Number(body.height_cm)
  const sex = typeof body.sex === 'string' && body.sex.trim() ? body.sex.trim().toLowerCase() : null
  const age = body.age === '' || body.age === undefined || body.age === null ? null : Number(body.age)
  const goal = typeof body.goal === 'string' && body.goal.trim() ? body.goal.trim().toLowerCase() : null

  const errors: string[] = []
  if (!username) errors.push('username is required')
  if (username.length > 30) errors.push('username must be 30 characters or fewer')
  if (!isSpecialization(focusType)) errors.push(`focus_type must be one of: ${specializationList()}`)
  if (weightKg !== null && (!Number.isFinite(weightKg) || weightKg <= 0 || weightKg >= 500)) errors.push('weight_kg must be between 0 and 500')
  if (heightCm !== null && (!Number.isFinite(heightCm) || heightCm <= 0 || heightCm >= 300)) errors.push('height_cm must be between 0 and 300')
  if (sex !== null && !ALLOWED_SEX.includes(sex)) errors.push(`sex must be one of: ${ALLOWED_SEX.join(', ')}`)
  if (age !== null && (!Number.isInteger(age) || age <= 0 || age >= 120)) errors.push('age must be a whole number between 0 and 120')
  if (goal !== null && !ALLOWED_GOALS.includes(goal)) errors.push(`goal must be one of: ${ALLOWED_GOALS.join(', ')}`)
  const noticeVersion = typeof body.privacy_notice_version === 'string' ? body.privacy_notice_version : ''
  if (!noticeVersion) errors.push('Please read and acknowledge the privacy notice to create an account.')

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // The acknowledged version must be the current one, so the record shows the
  // notice the person actually saw.
  const { data: currentNotice } = await admin.rpc('current_notice_version', { p_consent_type: 'privacy_notice' })
  if (!currentNotice || currentNotice !== noticeVersion) {
    return new Response(JSON.stringify({
      success: false, code: 'NOTICE_VERSION_OUTDATED',
      error: 'The privacy notice was updated. Please reload the page and read the current version.'
    }), {
      status: 409,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data: existing } = await admin.from('users').select('id').eq('id', id).maybeSingle()
  if (existing) {
    return new Response(JSON.stringify({ success: true, alreadyExists: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // The starting rank is the tier-1 name of the chosen path, read from the
  // ladder rather than hardcoded. This used to be a literal 'Beginner', which
  // is the HYBRID tier-1 name — so a powerlifter signup started as "Beginner"
  // instead of "Iron Rookie". Harmless-looking while all four paths shared a
  // default; wrong for eight of the nine paths.
  const { data: startTier } = await admin
    .from('rank_thresholds')
    .select('rank_name')
    .eq('focus_type', focusType)
    .eq('tier_index', 1)
    .maybeSingle()

  if (!startTier) {
    return new Response(JSON.stringify({
      success: false,
      errors: [`No rank ladder is configured for "${focusType}". Please pick another path.`]
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { error } = await admin.from('users').insert({
    id,
    username,
    focus_type: focusType,
    weight_kg: weightKg,
    height_cm: heightCm,
    sex,
    age,
    goal,
    rank: startTier.rank_name,
    rank_sub_index: 1,
    xp: 0,
    streak: 0
  })

  if (error) {
    // public.users.username is UNIQUE, and a taken username is the one failure
    // here a user can actually cause and fix themselves — so it gets a message
    // written for them. Returning error.message raw surfaced Postgres' own
    // "duplicate key value violates unique constraint \"users_username_key\""
    // to the signup screen, which is both unhelpful and leaks schema details.
    const isDuplicateUsername = error.code === '23505' && /username/i.test(error.message)
    return new Response(JSON.stringify({
      success: false,
      error: isDuplicateUsername
        ? 'That username is already taken — pick another one.'
        : error.message,
      code: isDuplicateUsername ? 'USERNAME_TAKEN' : undefined
    }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Recorded after the profile row exists (user_consents references it). If
  // this fails, the app asks for the acknowledgement again at first login.
  const { error: consentError } = await admin.rpc('record_consent', {
    p_user_id: id, p_consent_type: 'privacy_notice', p_notice_version: noticeVersion
  })
  if (consentError) console.error('[register] consent record failed:', consentError.message)

  return new Response(JSON.stringify({ success: true, consent_recorded: !consentError }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
