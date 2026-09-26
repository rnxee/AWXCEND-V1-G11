import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

const ALLOWED_TABS = ['fitness', 'food']
const POST_LIMIT = 50

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
  const tab = (url.searchParams.get('tab') ?? '').trim()
  if (!ALLOWED_TABS.includes(tab)) {
    return new Response(JSON.stringify({ success: false, errors: [`tab must be one of: ${ALLOWED_TABS.join(', ')}`] }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // Always filters to approved, regardless of who's asking — including an
  // admin browsing the normal feed. Pending/rejected posts are only ever
  // visible through the moderation queue (get-pending-posts), a separate,
  // admin-gated view, never mixed into the public feed.
  const { data, error } = await admin
    .from('gymmunity_posts')
    .select('id, user_id, tab, title, content, image_url, ingredients, calories, protein, carbs, fat, created_at, users!inner(username, rank)')
    .eq('tab', tab)
    .eq('status', 'approved')
    // !inner above makes the author embed an inner join, so this removes a
    // deactivated author's POSTS from the feed rather than just their name.
    .is('users.deactivated_at', null)
    .order('created_at', { ascending: false })
    .limit(POST_LIMIT)

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, posts: data ?? [] }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
