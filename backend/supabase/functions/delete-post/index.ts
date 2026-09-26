import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'
import { postImagePath } from '../_shared/paging.ts'

// A user deletes one of their own Gymunnity posts (fitness or food tab).
//
//   POST { post_id }
//
// Only the author can delete, whatever the post's moderation status. The
// post's image is removed from the public bucket too, so a deleted post
// leaves no photo behind at its old URL.

const RL_MAX = 30
const RL_WINDOW_SECONDS = 300

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
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  if (!(await checkRateLimit(user.id, 'delete_post', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  if (!isUuid(body.post_id)) return json({ success: false, error: 'A valid post_id is required.' }, 400)

  const admin = getAdminClient()
  const { data: post, error: findError } = await admin
    .from('gymmunity_posts')
    .select('id, user_id, image_url')
    .eq('id', body.post_id)
    .maybeSingle()

  if (findError) return json({ success: false, error: 'Could not delete the post.' }, 500)
  // Same answer for "not found" and "not yours": no probing other users' posts.
  if (!post || post.user_id !== user.id) return json({ success: false, error: 'Post not found.' }, 404)

  const { error: deleteError } = await admin.from('gymmunity_posts').delete().eq('id', post.id).eq('user_id', user.id)
  if (deleteError) return json({ success: false, error: 'Could not delete the post.' }, 500)

  // Best effort: the post is gone either way; a leftover file is only storage.
  const path = postImagePath(post.image_url)
  if (path && path.startsWith(`${user.id}/`)) {
    await admin.storage.from('gymmunity-images').remove([path])
  }

  return json({ success: true, deleted: post.id })
})
