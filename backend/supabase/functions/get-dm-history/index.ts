import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { isUuid } from '../_shared/validation.ts'
import { parseBefore, parseLimit, pageResult } from '../_shared/paging.ts'

// Newest page first; ?before=<iso> fetches the page before it (scroll up).
// It used to read the OLDEST 200 ascending, hiding every newer message once a
// conversation passed 200.
const DEFAULT_LIMIT = 30
const MAX_LIMIT = 100

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
  const friendId = (url.searchParams.get('friend_id') ?? '').trim()
  if (!friendId) {
    return new Response(JSON.stringify({ success: false, error: 'friend_id is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  // Interpolated into the .or() filters below — reject anything that isn't a
  // clean UUID before it reaches the query string.
  if (!isUuid(friendId)) {
    return new Response(JSON.stringify({ success: false, error: 'friend_id must be a valid id' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const { data: friendship } = await admin
    .from('friendships')
    .select('status')
    .or(`and(requester_id.eq.${user.id},addressee_id.eq.${friendId}),and(requester_id.eq.${friendId},addressee_id.eq.${user.id})`)
    .maybeSingle()

  if (!friendship || friendship.status !== 'accepted') {
    return new Response(JSON.stringify({ success: false, error: 'You must be friends with this user to view messages' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const limit = parseLimit(url.searchParams.get('limit'), DEFAULT_LIMIT, MAX_LIMIT)
  const before = parseBefore(url.searchParams.get('before'))
  let query = admin
    .from('direct_messages')
    .select('*')
    .or(`and(sender_id.eq.${user.id},recipient_id.eq.${friendId}),and(sender_id.eq.${friendId},recipient_id.eq.${user.id})`)
    .order('created_at', { ascending: false })
    .limit(limit + 1)
  if (before) query = query.lt('created_at', before)
  const { data, error } = await query

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { items, has_more } = pageResult(data ?? [], limit)
  return new Response(JSON.stringify({ success: true, messages: items, has_more }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
