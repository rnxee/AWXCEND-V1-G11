import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// The shop.
//
//   GET                                   items, what you own, balance, and
//                                         whether a Streak Restore would help
//   POST { action: 'purchase', item_key, quantity, request_id }
//   POST { action: 'use', item_key, context_type?, context_id? }
//
// The price is never sent by the client — purchase_item reads it from
// shop_items — and request_id makes a purchase idempotent, so a double-tap
// charges once. Gold only ever comes from gameplay; there is no path here
// that takes real money.

const RL_MAX = 30
const RL_WINDOW_SECONDS = 300
const ITEM_KEY_RE = /^[a-z_]{2,40}$/
const CONTEXT_TYPES = ['mission_attempt', 'dungeon_run', 'streak']

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

// Database errors arrive as "CODE: human sentence"; the sentence is written
// for the player.
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
    const { data, error } = await admin.rpc('get_shop', { p_user_id: user.id })
    if (error) return json({ success: false, error: error.message }, 400)
    return json(data, 200)
  }

  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  if (!(await checkRateLimit(user.id, 'shop', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const itemKey = typeof body.item_key === 'string' ? body.item_key : ''
  if (!ITEM_KEY_RE.test(itemKey)) return json({ success: false, error: 'A valid item_key is required.' }, 400)

  let rpc: { name: string; args: Record<string, unknown> }

  if (body.action === 'purchase') {
    const quantity = Number(body.quantity ?? 1)
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 10) {
      return json({ success: false, error: 'quantity must be a whole number from 1 to 10.' }, 400)
    }
    if (!isUuid(body.request_id)) return json({ success: false, error: 'A request_id (UUID) is required.' }, 400)
    rpc = {
      name: 'purchase_item',
      args: { p_user_id: user.id, p_item_key: itemKey, p_quantity: quantity, p_request_id: body.request_id }
    }

  } else if (body.action === 'use') {
    const contextType = body.context_type ?? null
    if (contextType !== null && !CONTEXT_TYPES.includes(contextType)) {
      return json({ success: false, error: `context_type must be one of: ${CONTEXT_TYPES.join(', ')}.` }, 400)
    }
    const contextId = body.context_id ?? null
    if (contextId !== null && !isUuid(contextId)) {
      return json({ success: false, error: 'context_id must be a UUID.' }, 400)
    }
    rpc = {
      name: 'use_item',
      args: { p_user_id: user.id, p_item_key: itemKey, p_context_type: contextType, p_context_id: contextId }
    }

  } else {
    return json({ success: false, error: 'action must be purchase or use.' }, 400)
  }

  const { data, error } = await admin.rpc(rpc.name, rpc.args)
  if (error) return json({ success: false, error: playerMessage(error.message) }, 400)

  return json(data, 200)
})
