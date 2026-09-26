import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

const ALLOWED_ACTIONS = ['accept', 'decline']

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

  if (!(await checkRateLimit(user.id, 'respond_friend_request', 60, 600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const requestId = typeof body.request_id === 'string' ? body.request_id.trim() : ''
  const action = typeof body.action === 'string' ? body.action.trim() : ''

  const errors: string[] = []
  if (!requestId) errors.push('request_id is required')
  if (!ALLOWED_ACTIONS.includes(action)) errors.push(`action must be one of: ${ALLOWED_ACTIONS.join(', ')}`)
  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const { data: existing, error: fetchError } = await admin
    .from('friendships')
    .select('*')
    .eq('id', requestId)
    .single()

  if (fetchError || !existing) {
    return new Response(JSON.stringify({ success: false, error: 'Request not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Only the addressee can respond — the requester can't approve their own
  // request just by knowing the row id. Checked against the verified
  // session, never anything client-supplied.
  if (existing.addressee_id !== user.id) {
    return new Response(JSON.stringify({ success: false, error: 'Not your request to respond to' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  if (existing.status !== 'pending') {
    return new Response(JSON.stringify({ success: false, error: 'Request already resolved' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data: updated, error } = await admin
    .from('friendships')
    .update({ status: action === 'accept' ? 'accepted' : 'declined', responded_at: new Date().toISOString() })
    .eq('id', requestId)
    .select()
    .single()

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, friendship: updated }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
