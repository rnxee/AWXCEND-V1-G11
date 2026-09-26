import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'
import { dailyGoldKey } from '../_shared/gameDay.ts'
import { recordAdminAction } from '../_shared/audit.ts'
import { storagePathFromPublicUrl } from '../_shared/storagePaths.ts'

const IMAGE_BUCKET = 'gymmunity-images'

// Matches create-post: one award per author per game day (Asia/Manila).
const DAILY_POST_GOLD = 10

const ALLOWED_STATUSES = ['approved', 'rejected']

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

  // Role is checked server-side against the verified user's own row — never
  // trusted from the request body. Same rule as everywhere else: the client
  // can claim anything, only the DB row backing the verified token counts.
  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profileError || !hasPermission(profile?.role, 'moderate_posts')) {
    return new Response(JSON.stringify({ success: false, error: 'Moderator access required' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const body = await req.json().catch(() => ({}))
  const postId = typeof body.post_id === 'string' ? body.post_id.trim() : ''
  const newStatus = typeof body.status === 'string' ? body.status.trim() : ''

  const errors: string[] = []
  if (!postId) errors.push('post_id is required')
  if (!ALLOWED_STATUSES.includes(newStatus)) errors.push(`status must be one of: ${ALLOWED_STATUSES.join(', ')}`)

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data: existingPost, error: fetchError } = await admin
    .from('gymmunity_posts')
    .select('id, user_id, status, image_url')
    .eq('id', postId)
    .single()

  if (fetchError || !existingPost) {
    return new Response(JSON.stringify({ success: false, error: 'Post not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const wasPending = existingPost.status === 'pending'

  // A rejected post's image is in a PUBLIC bucket, so anyone holding its URL
  // could still open it. Remove the file, then clear the URL. If removal fails,
  // the URL is kept so the file isn't orphaned out of reach of a retry.
  let imageRemoved = false
  if (newStatus === 'rejected' && existingPost.image_url) {
    const path = storagePathFromPublicUrl(existingPost.image_url, IMAGE_BUCKET)
    if (path) {
      const { error: removeError } = await admin.storage.from(IMAGE_BUCKET).remove([path])
      if (removeError) console.error('[moderate-post] image removal failed:', removeError.message)
      else imageRemoved = true
    } else {
      console.error('[moderate-post] image_url is not a file in this bucket; left in place')
    }
  }

  const { data: updatedPost, error: updateError } = await admin
    .from('gymmunity_posts')
    .update(imageRemoved ? { status: newStatus, image_url: null } : { status: newStatus })
    .eq('id', postId)
    .select()
    .single()

  if (updateError) {
    return new Response(JSON.stringify({ success: false, error: updateError.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Gold fires only on the pending -> approved transition, and only once
  // per author per day — so approving a spam-then-appeal post after the
  // author already got today's gold from an earlier post awards nothing.
  let goldAwarded = 0
  if (wasPending && newStatus === 'approved') {
    // Keyed by the AUTHOR and the game day, the same key create-post uses, so
    // approving a post cannot pay the author a second time for a day they
    // have already been paid for.
    const { data: goldResult, error: goldError } = await admin.rpc('award_gold', {
      p_user_id: existingPost.user_id,
      p_amount: DAILY_POST_GOLD,
      p_reason: 'daily_community_post',
      p_source_id: existingPost.id,
      p_idempotency_key: dailyGoldKey('daily_community_post', existingPost.user_id)
    })
    if (goldError) console.error('[moderate-post] gold award failed:', goldError.message)
    goldAwarded = goldResult?.awarded ? DAILY_POST_GOLD : 0
  }

  const auditRecorded = await recordAdminAction(admin, {
    actorUserId: user.id,
    action: newStatus === 'approved' ? 'post.approve' : 'post.reject',
    targetType: 'gymmunity_post',
    targetId: existingPost.id,
    metadata: {
      author_user_id: existingPost.user_id,
      previous_status: existingPost.status,
      new_status: newStatus,
      had_image: Boolean(existingPost.image_url),
      image_removed: imageRemoved
    }
  })

  return new Response(JSON.stringify({
    success: true, post: updatedPost, gold_awarded: goldAwarded, image_removed: imageRemoved, audit_recorded: auditRecorded
  }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
