import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { parseBefore, parseLimit, pageResult } from '../_shared/paging.ts'

// Gymunnity chat history, newest page first.
//
//   GET ?limit=30                 the latest messages
//   GET ?before=<iso>&limit=30    the page before an older message (scroll up)
//
// Returns { success, messages (oldest first), has_more }. It used to read the
// OLDEST 50 rows ascending, so once the chat passed 50 messages a reload
// showed old ones and hid every newer one. user_id and id are included so the
// chat can open the sender's profile or report a specific message.

const DEFAULT_LIMIT = 30
const MAX_LIMIT = 100

function json(body: unknown, status = 200) {
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

  const params = new URL(req.url).searchParams
  const limit = parseLimit(params.get('limit'), DEFAULT_LIMIT, MAX_LIMIT)
  const before = parseBefore(params.get('before'))

  let query = getAdminClient()
    .from('chat_messages')
    .select('id, user_id, username, rank_badge, message, created_at')
    .eq('flagged', false)
    .order('created_at', { ascending: false })
    .limit(limit + 1)
  if (before) query = query.lt('created_at', before)

  const { data, error } = await query
  if (error) return json({ success: false, error: 'Could not load messages.' }, 400)

  const { items, has_more } = pageResult(data ?? [], limit)
  return json({ success: true, messages: items, has_more })
})
