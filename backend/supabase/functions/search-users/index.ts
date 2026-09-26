import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'

const RESULT_LIMIT = 20
const MIN_QUERY_LENGTH = 2

// Slows scripted enumeration of the user directory. A person searching for
// friends types a handful of queries; 40 in 5 minutes leaves that untouched.
const RL_MAX = 40
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

  if (!(await checkRateLimit(user.id, 'search_users', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const url = new URL(req.url)
  const query = (url.searchParams.get('query') ?? '').trim()
  if (query.length < MIN_QUERY_LENGTH) {
    return new Response(JSON.stringify({ success: true, results: [] }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // Public-directory search — only ever returns the same fields anyone's
  // profile card shows elsewhere in the app, never biometric/private columns.
  const { data, error } = await admin
    .from('users')
    .select('id, username, rank, focus_type, avatar_url')
    .ilike('username', `%${query}%`)
    .neq('id', user.id)
    // Deactivated accounts keep all their data but are hidden from every
    // surface where another user could find them, until they reactivate.
    .is('deactivated_at', null)
    .limit(RESULT_LIMIT)

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const results = data ?? []

  // Batch-fetch friendship rows against every result at once (not N+1) so
  // the search UI can show "Friends" / "Pending" instead of letting someone
  // send a request that just bounces off a duplicate-relationship error.
  const resultIds = results.map(r => r.id)
  const { data: friendships } = resultIds.length
    ? await admin.from('friendships').select('*')
        .or(`requester_id.in.(${resultIds.join(',')}),addressee_id.in.(${resultIds.join(',')})`)
    : { data: [] }

  const statusByOtherId = new Map<string, string>()
  for (const f of friendships ?? []) {
    // Only rows that actually involve the current user are relevant — the
    // OR filter above can also return rows between two OTHER result users.
    if (f.requester_id !== user.id && f.addressee_id !== user.id) continue
    const otherId = f.requester_id === user.id ? f.addressee_id : f.requester_id
    if (!resultIds.includes(otherId)) continue
    const status = f.status === 'accepted' ? 'accepted' : f.status === 'pending' ? (f.requester_id === user.id ? 'pending_outgoing' : 'pending_incoming') : 'none'
    statusByOtherId.set(otherId, status)
  }

  const enriched = results.map(r => ({ ...r, friendship_status: statusByOtherId.get(r.id) ?? 'none' }))

  return new Response(JSON.stringify({ success: true, results: enriched }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
