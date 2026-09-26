import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

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

  const admin = getAdminClient()

  const { data: rows, error } = await admin
    .from('friendships')
    .select('*')
    .or(`requester_id.eq.${user.id},addressee_id.eq.${user.id}`)
    .order('created_at', { ascending: false })

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const friendships = rows ?? []

  // friendships has two FKs to users (requester_id, addressee_id), which
  // PostgREST can't auto-embed without an FK-name hint — simpler and more
  // robust to just batch-fetch the "other side" user rows ourselves and
  // stitch them together here than to depend on that disambiguation syntax.
  const otherUserIds = [...new Set(friendships.map(f => f.requester_id === user.id ? f.addressee_id : f.requester_id))]
  const { data: otherUsers } = otherUserIds.length
    ? await admin.from('users').select('id, username, rank, focus_type, avatar_url').in('id', otherUserIds).is('deactivated_at', null)
    : { data: [] }
  const usersById = new Map((otherUsers ?? []).map(u => [u.id, u]))

  const friends: unknown[] = []
  const incomingRequests: unknown[] = []
  const outgoingRequests: unknown[] = []

  for (const f of friendships) {
    const isRequester = f.requester_id === user.id
    const otherId = isRequester ? f.addressee_id : f.requester_id
    const otherUser = usersById.get(otherId)
    if (!otherUser) continue // other account deleted — skip rather than error the whole list

    const entry = { friendship_id: f.id, user: otherUser, created_at: f.created_at }
    if (f.status === 'accepted') friends.push(entry)
    else if (f.status === 'pending' && isRequester) outgoingRequests.push(entry)
    else if (f.status === 'pending' && !isRequester) incomingRequests.push(entry)
  }

  return new Response(JSON.stringify({ success: true, friends, incomingRequests, outgoingRequests }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
