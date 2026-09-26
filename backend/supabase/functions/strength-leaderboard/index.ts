import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import {
  RANKABLE_LIFTS,
  isRankableLift,
  resolveStrengthRank
} from '../_shared/strengthStandards.ts'
import { shapeStrengthEntry } from '../_shared/strengthPrivacy.ts'

// Mode B of the dual-mode leaderboard: peak strength, ranked separately from
// the XP/consistency board.
//
// Two things this endpoint refuses to do, both deliberate:
//
//  * It never blends absolute and relative strength into one number. Raw
//    kilograms and bodyweight multiples answer different questions; a lifter
//    can legitimately top one board and not the other, and averaging them
//    would answer neither. `mode` picks which board you are looking at.
//
//  * It never reveals another lifter's bodyweight. Bodyweight itself is sent
//    only to its owner, and bodyweight multiples and tiers (which, with a
//    kilogram lift, give bodyweight away) only for lifters who explicitly
//    joined the relative board (users.relative_leaderboard_opt_in). See
//    _shared/strengthPrivacy.ts.
//
//  * It never mixes lifts. A curl and a deadlift are not comparable in
//    kilograms, and the cross-exercise normalisation that would make them
//    comparable does not exist yet. One board per lift, plus the Big 3 total
//    which needs no normalisation because it is an established standard.

const LEADERBOARD_LIMIT = 50
const MODES = ['absolute', 'relative'] as const

// A read-only board, so the window is generous — it exists to stop a script
// hammering the endpoint, not to ration normal browsing between lifts and
// modes.
const RL_MAX = 60
const RL_WINDOW_SECONDS = 60

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

  if (!(await checkRateLimit(user.id, 'strength_leaderboard', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const url = new URL(req.url)
  const exercise = (url.searchParams.get('exercise') ?? 'squat').trim().toLowerCase()
  const mode = (url.searchParams.get('mode') ?? 'absolute').trim().toLowerCase()
  const verifiedOnly = url.searchParams.get('verified_only') === 'true'

  const errors: string[] = []
  if (!isRankableLift(exercise)) {
    errors.push(`exercise must be one of: ${RANKABLE_LIFTS.join(', ')}`)
  }
  if (!(MODES as readonly string[]).includes(mode)) {
    errors.push(`mode must be one of: ${MODES.join(', ')}`)
  }
  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const sortColumn = mode === 'relative' ? 'relative_e1rm' : 'e1rm_kg'

  const { data: viewer } = await admin.from('users').select('relative_leaderboard_opt_in').eq('id', user.id).maybeSingle()
  const viewerOptedIn = viewer?.relative_leaderboard_opt_in === true
  const resolveRank = (relative: number | string | null) => resolveStrengthRank(exercise, relative)

  // Reads the PR view, so one lifter appears once per board with their best
  // lift rather than once per set.
  let query = admin
    .from('strength_prs')
    .select('user_id, exercise, weight_kg, reps, e1rm_kg, relative_e1rm, bodyweight_kg, form_verified, workout_source, achieved_at')
    .eq('exercise', exercise)
    .order(sortColumn, { ascending: false, nullsFirst: false })
    .limit(LEADERBOARD_LIMIT)

  // The relative board can only include lifters whose bodyweight is known.
  // Including them with a null ratio would sort them arbitrarily and imply a
  // rank the data does not support.
  if (mode === 'relative') {
    // Only lifters who chose to be on it. An empty list matches nobody.
    const { data: optedIn } = await admin.from('users').select('id')
      .eq('relative_leaderboard_opt_in', true).is('deactivated_at', null)
    const ids = (optedIn ?? []).map((u) => u.id)
    query = query.not('relative_e1rm', 'is', null)
      .in('user_id', ids.length > 0 ? ids : ['00000000-0000-0000-0000-000000000000'])
  }

  // "Form verified" means the movement was camera-observed above the quality
  // threshold. It does NOT mean the load was verified — nothing in this
  // system can check the plates. The filter is offered because it is the
  // strictest evidence available, not because it makes a record certain.
  if (verifiedOnly) query = query.eq('form_verified', true)

  const { data: prs, error } = await query

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const rows = prs ?? []

  // Usernames are joined separately rather than embedded, because
  // strength_prs is a view and PostgREST cannot infer a foreign key through
  // it to build a nested select.
  const userIds = [...new Set(rows.map((r) => r.user_id))]
  const { data: profiles } = userIds.length
    ? await admin.from('users').select('id, username, focus_type, relative_leaderboard_opt_in').in('id', userIds).is('deactivated_at', null)
    : { data: [] }

  const byId = new Map((profiles ?? []).map((p) => [p.id, p]))

  // A deactivated lifter's records stay in strength_prs — deactivation is
  // reversible, so nothing is deleted — but they must not appear on a public
  // board. byId holds only ACTIVE profiles, so filtering on it drops them.
  const visibleRows = rows.filter((r) => byId.has(r.user_id))

  const entries = visibleRows.map((row, i) => {
    const profile = byId.get(row.user_id)

    return {
      position: i + 1,
      username: profile?.username ?? 'Unknown',
      focus_type: profile?.focus_type ?? null,
      ...shapeStrengthEntry(row, {
        isSelf: row.user_id === user.id,
        relativeOptIn: profile?.relative_leaderboard_opt_in === true,
        resolveRank
      })
    }
  })

  // The requesting user's own standing, even when they are outside the top 50
  // — otherwise the board is useless to everyone not already on it.
  const ownRowIndex = visibleRows.findIndex((r) => r.user_id === user.id)
  let own = ownRowIndex >= 0 ? entries[ownRowIndex] : null

  if (!own) {
    const { data: ownPr } = await admin
      .from('strength_prs')
      .select('exercise, weight_kg, reps, e1rm_kg, relative_e1rm, bodyweight_kg, form_verified, workout_source, achieved_at')
      .eq('exercise', exercise)
      .eq('user_id', user.id)
      .maybeSingle()

    if (ownPr) {
      own = {
        position: null, // outside the returned page
        username: null,
        focus_type: null,
        ...shapeStrengthEntry({ ...ownPr, user_id: user.id }, { isSelf: true, relativeOptIn: viewerOptedIn, resolveRank })
      }
    }
  }

  return new Response(JSON.stringify({
    success: true,
    exercise,
    mode,
    verified_only: verifiedOnly,
    viewer_relative_opt_in: viewerOptedIn,
    entries,
    own,
    rankable_lifts: RANKABLE_LIFTS
  }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
