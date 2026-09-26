import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

const MAX_MESSAGE_LENGTH = 2000

// Generous enough for fast back-and-forth chat, low enough to blunt a script
// blasting a friend (or, combined with the friend-gate, the whole table).
const RL_MAX = 60
const RL_WINDOW_SECONDS = 300

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

  if (!(await checkRateLimit(user.id, 'send_dm', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const recipientId = typeof body.recipient_id === 'string' ? body.recipient_id.trim() : ''
  const message = typeof body.message === 'string' ? body.message.trim() : ''

  const errors: string[] = []
  if (!recipientId) errors.push('recipient_id is required')
  else if (!isUuid(recipientId)) errors.push('recipient_id must be a valid id')
  if (!message) errors.push('message is required')
  if (message.length > MAX_MESSAGE_LENGTH) errors.push(`message must be ${MAX_MESSAGE_LENGTH} characters or fewer`)
  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // DMs are friend-gated — checked server-side against the friendship table,
  // never trusted from the client. Keeps this a chat-with-friends feature
  // rather than an open inbox strangers can spam.
  const { data: friendship } = await admin
    .from('friendships')
    .select('status')
    .or(`and(requester_id.eq.${user.id},addressee_id.eq.${recipientId}),and(requester_id.eq.${recipientId},addressee_id.eq.${user.id})`)
    .maybeSingle()

  if (!friendship || friendship.status !== 'accepted') {
    return new Response(JSON.stringify({ success: false, error: 'You must be friends with this user to message them' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data, error } = await admin
    .from('direct_messages')
    .insert({ sender_id: user.id, recipient_id: recipientId, message })
    .select()
    .single()

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, message: data }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
