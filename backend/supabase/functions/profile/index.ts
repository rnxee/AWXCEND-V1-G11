import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { computeLevel } from '../_shared/leveling.ts'

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

  const admin = getAdminClient()

  // The first-run app tour was finished or skipped. Only ever the caller's
  // own row, and only the first time (a replay never re-stamps it).
  if (req.method === 'POST') {
    const body = await req.json().catch(() => ({}))
    if (body.action !== 'tour_done') {
      return new Response(JSON.stringify({ success: false, error: 'action must be tour_done.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    const stampedAt = new Date().toISOString()
    const { error } = await admin.from('users').update({ tour_completed_at: stampedAt })
      .eq('id', user.id).is('tour_completed_at', null)
    return new Response(JSON.stringify(error ? { success: false, error: 'Could not save.' } : { success: true }), {
      status: error ? 500 : 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const [profileRes, workoutsRes, rankHistoryRes, goldRes, pendingFriendRequestsRes, specializationXpRes, strengthPrsRes, streakRes, streakShieldsRes] = await Promise.all([
    admin.from('users').select('*').eq('id', user.id).single(),
    // Capped well above what anyone would realistically log, not left
    // unbounded — the "show all" profile toggle needs more than the old
    // 50-row cap allowed, but a hard ceiling still protects against an
    // unbounded query on an account with years of history.
    admin.from('workout_logs').select('*').eq('user_id', user.id).order('logged_at', { ascending: false }).limit(1000),
    admin.from('rank_history').select('*').eq('user_id', user.id).order('achieved_at', { ascending: false }).limit(20),
    // Gold balance is never a stored column (same reasoning as XP forgery
    // patched earlier) — it's always derived by summing the ledger. Row
    // count per user stays small (at most one row per day per reason), so
    // summing in JS here is simpler than relying on a specific PostgREST
    // aggregate syntax and just as fast at this scale.
    admin.from('gold_ledger').select('amount').eq('user_id', user.id),
    // Powers the notification dot on the Friends icon — a count query here
    // is far cheaper than the Dashboard calling get-friends just to check
    // for a badge, since profile already loads on every Dashboard visit.
    admin.from('friendships').select('id', { count: 'exact', head: true }).eq('addressee_id', user.id).eq('status', 'pending'),
    // Per-path XP. Rank is resolved from the ACTIVE path's total, not from
    // lifetime users.xp — a user who has switched paths has more lifetime XP
    // than they have earned on the path they are currently on.
    admin.from('user_specialization_xp').select('focus_type, xp').eq('user_id', user.id),
    // Own strength PRs. These were visible on the leaderboard for everyone
    // else before they were visible to the user on their own profile.
    admin.from('strength_prs')
      .select('exercise, weight_kg, reps, e1rm_kg, relative_e1rm, bodyweight_kg, form_verified, workout_source, achieved_at')
      .eq('user_id', user.id)
      .order('e1rm_kg', { ascending: false }),
    // The streak, computed server-side in the game's timezone (Asia/Manila)
    // and including any day a Streak Restore covers. The client keeps its own
    // copy of the same rule for instant feedback, but this is the figure that
    // decides whether a Streak Restore is worth selling.
    admin.rpc('compute_streak', { p_user_id: user.id }),
    admin.from('streak_shields').select('covered_date').eq('user_id', user.id)
  ])

  if (profileRes.error) {
    return new Response(JSON.stringify({ success: false, error: profileRes.error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const goldBalance = (goldRes.data ?? []).reduce((sum, row) => sum + row.amount, 0)

  const specializationXpRows = specializationXpRes.data ?? []
  const activePathXp = specializationXpRows
    .find((row) => row.focus_type === profileRes.data.focus_type)?.xp ?? 0

  return new Response(JSON.stringify({
    profile: {
      ...profileRes.data,
      // Flattened onto the profile so the client does not have to know the
      // shape of the per-path table just to render a rank badge.
      specialization_xp: activePathXp
    },
    // The full set, so the profile screen can show progress on paths the user
    // has trained before without a second request.
    specializationXp: specializationXpRows,
    strengthPrs: strengthPrsRes.data ?? [],
    workouts: workoutsRes.data ?? [],
    rankHistory: rankHistoryRes.data ?? [],
    goldBalance,
    pendingFriendRequests: pendingFriendRequestsRes.count ?? 0,
    levelInfo: computeLevel(profileRes.data.xp),
    // The authoritative streak: computed in the game's timezone and counting
    // any day a Streak Restore covers. The client mirrors the same rule for
    // instant feedback, but this is the figure a purchase has to move.
    streak: streakRes.data ?? null,
    streakShields: (streakShieldsRes.data ?? []).map((row) => row.covered_date)
  }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
