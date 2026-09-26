import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

// The mission board: every active chapter, which levels are unlocked, which
// are cleared (and at what grade), and any attempt still in progress.
// Unlock state is derived from mission_clears inside get_mission_board, so
// the client never decides what a player is allowed to start.

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

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()
  const { data, error } = await admin.rpc('get_mission_board', { p_user_id: user.id })
  if (error) return json({ success: false, error: error.message }, 400)

  return json(data, 200)
})
