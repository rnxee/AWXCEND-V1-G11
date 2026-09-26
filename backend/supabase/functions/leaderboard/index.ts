import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

import { isSpecialization, specializationList } from '../_shared/specializations.ts'

const LEADERBOARD_LIMIT = 50

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
  const focusType = (url.searchParams.get('focus_type') ?? '').trim().toLowerCase()
  if (!isSpecialization(focusType)) {
    return new Response(JSON.stringify({ success: false, errors: [`focus_type must be one of: ${specializationList()}`] }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // Segmented by focus_type — a powerlifter's XP (heavy, low-rep, slow to
  // rack up) isn't comparable to a calisthenics athlete's (bodyweight,
  // high-rep), so one global board would just be a proxy for "who trains
  // the highest-multiplier exercises," not who's doing best in their lane.
  const { data, error } = await admin
    .from('users')
    .select('username, rank, rank_sub_index, xp')
    .eq('focus_type', focusType)
    // Deactivated accounts keep all their data but are hidden from every
    // surface where another user could find them, until they reactivate.
    .is('deactivated_at', null)
    .order('xp', { ascending: false })
    .limit(LEADERBOARD_LIMIT)

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify(data ?? []), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
