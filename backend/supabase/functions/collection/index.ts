import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// What a player has collected, and what they are wearing.
//
//   GET                                    everything they own
//   POST { collectible_id, equipped }      wear it, or take it off
//
// Collectibles are only ever granted server-side, inside the transaction that
// settles a Dungeon. There is no endpoint here that can create one.

const RL_MAX = 40
const RL_WINDOW_SECONDS = 300

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()

  if (req.method === 'GET') {
    const { data, error } = await admin.rpc('get_collection', { p_user_id: user.id })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 400)
    return json(data, 200)
  }

  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  if (!(await checkRateLimit(user.id, 'collection', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  if (!isUuid(body.collectible_id)) {
    return json({ success: false, error: 'A valid collectible_id is required.' }, 400)
  }
  if (typeof body.equipped !== 'boolean') {
    return json({ success: false, error: 'equipped must be true or false.' }, 400)
  }

  const { data, error } = await admin.rpc('equip_collectible', {
    p_user_id: user.id,
    p_collectible_id: body.collectible_id,
    p_equipped: body.equipped
  })
  if (error) return json({ success: false, error: playerMessage(error.message) }, 400)

  return json(data, 200)
})
