import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

// The Dungeon board: who has closed the most gates, or dealt the most damage
// doing it. Read-only and entirely derived from dungeon_clears and
// dungeon_runs, so there is nothing here a client could influence beyond
// choosing which of the two orderings to look at.
//
//   GET ?scope=clears|damage

const SCOPES = ['clears', 'damage']

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'GET') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const url = new URL(req.url)
  const scope = url.searchParams.get('scope') ?? 'clears'
  if (!SCOPES.includes(scope)) {
    return json({ success: false, error: `scope must be one of: ${SCOPES.join(', ')}.` }, 400)
  }

  const admin = getAdminClient()
  const { data, error } = await admin.rpc('get_dungeon_leaderboard', {
    p_user_id: user.id,
    p_scope: scope,
    p_limit: 50
  })
  if (error) return json({ success: false, error: error.message }, 400)

  return json(data, 200)
})
