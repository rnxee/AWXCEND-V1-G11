import { corsHeaders } from '../_shared/cors.ts'
import { trainingHistoryStatus } from '../_shared/verificationRules.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { computeLevel } from '../_shared/leveling.ts'
import { isUuid } from '../_shared/validation.ts'

const WORKOUT_PREVIEW_LIMIT = 10

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

  const url = new URL(req.url)
  const targetId = (url.searchParams.get('user_id') ?? '').trim()
  if (!targetId) {
    return new Response(JSON.stringify({ success: false, error: 'user_id is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  // Interpolated into a friendship .or() filter further down — validate shape.
  if (!isUuid(targetId)) {
    return new Response(JSON.stringify({ success: false, error: 'user_id must be a valid id' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // Deliberately narrow field list — this is what a stranger is allowed to
  // see about someone else. weight/height/sex/age/goal/role stay private,
  // unlike the self `profile` function which returns everything about you.
  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('id, username, avatar_url, bio, focus_type, rank, rank_sub_index, xp, streak, created_at, strength, agility, vitality')
    .eq('id', targetId)
    // Deactivated accounts keep all their data but are hidden from every
    // surface where another user could find them, until they reactivate.
    .is('deactivated_at', null)
    .maybeSingle()

  if (profileError) {
    return new Response(JSON.stringify({ success: false, error: profileError.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  if (!profile) {
    return new Response(JSON.stringify({ success: false, error: 'User not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const [workoutsRes, friendshipRes] = await Promise.all([
    admin.from('workout_logs').select('exercise, sets, reps, xp_earned, workout_source, logged_at')
      .eq('user_id', targetId).order('logged_at', { ascending: false }).limit(WORKOUT_PREVIEW_LIMIT),
    targetId === user.id
      ? Promise.resolve({ data: null })
      : admin.from('friendships').select('*')
          .or(`and(requester_id.eq.${user.id},addressee_id.eq.${targetId}),and(requester_id.eq.${targetId},addressee_id.eq.${user.id})`)
          .maybeSingle()
  ])

  // Collapses the friendship row into a single status the frontend can
  // switch on directly, from the viewer's perspective specifically —
  // "pending_outgoing" (viewer is waiting) reads very differently in the UI
  // than "pending_incoming" (viewer has a decision to make), even though
  // both are just status='pending' rows with the requester on different sides.
  let friendshipStatus: 'self' | 'none' | 'accepted' | 'pending_outgoing' | 'pending_incoming' = 'none'
  if (targetId === user.id) {
    friendshipStatus = 'self'
  } else if (friendshipRes.data) {
    const f = friendshipRes.data
    if (f.status === 'accepted') friendshipStatus = 'accepted'
    else if (f.status === 'pending') friendshipStatus = f.requester_id === user.id ? 'pending_outgoing' : 'pending_incoming'
  }

  // Only whether each status applies — never counts, documents or reviewers.
  // Coach verification and training history are separate from form_verified.
  const { data: publicVerification } = await admin.rpc('get_public_verification', { p_user_id: targetId })
  const verification = {
    coach_verified: Boolean(publicVerification?.coach_verified_at),
    coach_verified_at: publicVerification?.coach_verified_at ?? null,
    consistent_training_history: trainingHistoryStatus(publicVerification?.training_history ?? null).qualifies
  }

  return new Response(JSON.stringify({
    success: true,
    profile,
    verification,
    recentWorkouts: workoutsRes.data ?? [],
    friendshipStatus,
    levelInfo: computeLevel(profile.xp)
  }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
