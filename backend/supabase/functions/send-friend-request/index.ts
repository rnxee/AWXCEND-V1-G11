import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// No legitimate reason to fire many friend requests quickly — 30/hour throttles
// spray-request spam and userbase-enumeration-via-requests without ever
// bothering a normal user.
const RL_MAX = 30
const RL_WINDOW_SECONDS = 3600

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

  if (!(await checkRateLimit(user.id, 'send_friend_request', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const addresseeId = typeof body.addressee_id === 'string' ? body.addressee_id.trim() : ''

  if (!addresseeId) {
    return new Response(JSON.stringify({ success: false, error: 'addressee_id is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  if (!isUuid(addresseeId)) {
    return new Response(JSON.stringify({ success: false, error: 'addressee_id must be a valid id' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  if (addresseeId === user.id) {
    return new Response(JSON.stringify({ success: false, error: 'You cannot friend yourself' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const { data: addressee } = await admin.from('users').select('id').eq('id', addresseeId).is('deactivated_at', null).maybeSingle()
  if (!addressee) {
    return new Response(JSON.stringify({ success: false, error: 'User not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // The unique index is on the unordered pair, so only one row can ever
  // exist between these two users regardless of direction — fetch it first
  // so we can branch instead of hitting the constraint blind.
  const { data: existing } = await admin
    .from('friendships')
    .select('*')
    .or(`and(requester_id.eq.${user.id},addressee_id.eq.${addresseeId}),and(requester_id.eq.${addresseeId},addressee_id.eq.${user.id})`)
    .maybeSingle()

  if (existing) {
    if (existing.status === 'accepted') {
      return new Response(JSON.stringify({ success: false, error: 'Already friends' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    if (existing.status === 'pending') {
      if (existing.requester_id === addresseeId) {
        // They already requested us — treat our request as acceptance
        // instead of erroring, so the UI doesn't need to special-case this.
        const { data: accepted, error: acceptError } = await admin
          .from('friendships')
          .update({ status: 'accepted', responded_at: new Date().toISOString() })
          .eq('id', existing.id)
          .select()
          .single()
        if (acceptError) {
          return new Response(JSON.stringify({ success: false, error: acceptError.message }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          })
        }
        return new Response(JSON.stringify({ success: true, status: 'accepted', friendship: accepted }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }
      return new Response(JSON.stringify({ success: false, error: 'Request already sent' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    // status === 'declined' — allow re-requesting by resetting the existing row.
    const { data: retried, error: retryError } = await admin
      .from('friendships')
      .update({ requester_id: user.id, addressee_id: addresseeId, status: 'pending', responded_at: null })
      .eq('id', existing.id)
      .select()
      .single()
    if (retryError) {
      return new Response(JSON.stringify({ success: false, error: retryError.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    return new Response(JSON.stringify({ success: true, status: 'pending', friendship: retried }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data: created, error } = await admin
    .from('friendships')
    .insert({ requester_id: user.id, addressee_id: addresseeId, status: 'pending' })
    .select()
    .single()

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, status: 'pending', friendship: created }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
