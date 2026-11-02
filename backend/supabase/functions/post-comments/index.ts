import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkComment, isReaction } from '../_shared/commentRules.ts'
import { cleanText, isUuid } from '../_shared/validation.ts'

const RESULT_LIMIT = 200

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

async function visiblePost(admin: ReturnType<typeof getAdminClient>, postId: string, userId: string) {
  const { data } = await admin.from('gymmunity_posts').select('id, user_id, status').eq('id', postId).maybeSingle()
  return data && (data.status === 'approved' || data.user_id === userId) ? data : null
}

async function listComments(admin: ReturnType<typeof getAdminClient>, postId: string, userId: string) {
  const { data: rows, error } = await admin.from('gymmunity_comments')
    .select('id, post_id, user_id, parent_comment_id, content, created_at, updated_at, edited_at')
    .eq('post_id', postId).order('created_at', { ascending: true }).limit(RESULT_LIMIT)
  if (error) throw new Error(error.message)
  const comments = rows ?? []
  const ids = [...new Set(comments.map(comment => comment.user_id))]
  const { data: users } = ids.length
    ? await admin.from('users').select('id, username, avatar_url').in('id', ids)
    : { data: [] }
  const byId = new Map((users ?? []).map(user => [user.id, user]))
  const commentIds = comments.map(comment => comment.id)
  const { data: reactions } = commentIds.length
    ? await admin.from('gymmunity_comment_reactions').select('comment_id, user_id, reaction').in('comment_id', commentIds)
    : { data: [] }
  const reactionCounts = new Map<string, Record<string, number>>()
  const mine = new Map<string, string>()
  for (const reaction of reactions ?? []) {
    const counts = reactionCounts.get(reaction.comment_id) ?? {}
    counts[reaction.reaction] = (counts[reaction.reaction] ?? 0) + 1
    reactionCounts.set(reaction.comment_id, counts)
    if (reaction.user_id === userId) mine.set(reaction.comment_id, reaction.reaction)
  }
  return comments.map(comment => ({ ...comment, user: byId.get(comment.user_id) ?? { username: 'deleted user' },
    reaction_counts: reactionCounts.get(comment.id) ?? {}, my_reaction: mine.get(comment.id) ?? null }))
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  if (!(await checkRateLimit(user.id, 'post_comments', 120, 600))) return rateLimitResponse(corsHeaders)

  const admin = getAdminClient()
  if (req.method === 'GET') {
    const postId = new URL(req.url).searchParams.get('post_id')?.trim() ?? ''
    if (!isUuid(postId)) return json({ success: false, error: 'A valid post_id is required' }, 400)
    if (!await visiblePost(admin, postId, user.id)) return json({ success: false, error: 'Post not found.' }, 404)
    try {
      return json({ success: true, comments: await listComments(admin, postId, user.id) })
    } catch (error) {
      return json({ success: false, error: error instanceof Error ? error.message : 'Could not load comments' }, 400)
    }
  }
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const body = await req.json().catch(() => ({}))
  const action = typeof body.action === 'string' ? body.action.trim() : 'add'
  if (action === 'edit') {
    const commentId = typeof body.comment_id === 'string' ? body.comment_id.trim() : ''
    if (!isUuid(commentId)) return json({ success: false, error: 'A valid comment_id is required' }, 400)
    const checked = checkComment(cleanText(body.content))
    if (checked.error) return json({ success: false, error: checked.error }, 400)
    const { data: existing } = await admin.from('gymmunity_comments')
      .select('id, post_id, user_id').eq('id', commentId).maybeSingle()
    if (!existing || existing.user_id !== user.id || !await visiblePost(admin, existing.post_id, user.id)) {
      return json({ success: false, error: 'Comment not found.' }, 404)
    }
    const { data: updated, error } = await admin.from('gymmunity_comments').update({
      content: checked.text, updated_at: new Date().toISOString(), edited_at: new Date().toISOString(),
    }).eq('id', commentId).eq('user_id', user.id).select().single()
    if (error) return json({ success: false, error: error.message }, 400)
    return json({ success: true, comment: updated })
  }
  if (action === 'react') {
    const commentId = typeof body.comment_id === 'string' ? body.comment_id.trim() : ''
    const reaction = body.reaction == null || body.reaction === '' ? null : String(body.reaction).trim()
    if (!isUuid(commentId)) return json({ success: false, error: 'A valid comment_id is required' }, 400)
    if (reaction !== null && !isReaction(reaction)) return json({ success: false, error: 'Unsupported reaction' }, 400)
    const { data: comment } = await admin.from('gymmunity_comments').select('post_id').eq('id', commentId).maybeSingle()
    if (!comment || !await visiblePost(admin, comment.post_id, user.id)) return json({ success: false, error: 'Comment not found.' }, 404)
    if (reaction === null) {
      const { error } = await admin.from('gymmunity_comment_reactions').delete().eq('comment_id', commentId).eq('user_id', user.id)
      if (error) return json({ success: false, error: error.message }, 400)
    } else {
      const { error } = await admin.from('gymmunity_comment_reactions').upsert({
        comment_id: commentId, user_id: user.id, reaction, updated_at: new Date().toISOString(),
      }, { onConflict: 'comment_id,user_id' })
      if (error) return json({ success: false, error: error.message }, 400)
    }
    return json({ success: true, reaction })
  }
  if (action !== 'add') return json({ success: false, error: 'Unsupported comment action' }, 400)
  const postId = typeof body.post_id === 'string' ? body.post_id.trim() : ''
  if (!isUuid(postId)) return json({ success: false, error: 'A valid post_id is required' }, 400)
  if (!await visiblePost(admin, postId, user.id)) return json({ success: false, error: 'Post not found.' }, 404)
  const checked = checkComment(cleanText(body.content))
  if (checked.error) return json({ success: false, error: checked.error }, 400)

  const parentId = body.parent_comment_id == null ? null : String(body.parent_comment_id).trim()
  if (parentId && !isUuid(parentId)) return json({ success: false, error: 'parent_comment_id must be a valid id' }, 400)
  if (parentId) {
    const { data: parent } = await admin.from('gymmunity_comments').select('id').eq('id', parentId).eq('post_id', postId).maybeSingle()
    if (!parent) return json({ success: false, error: 'Parent comment not found.' }, 404)
  }
  const { data: comment, error } = await admin.from('gymmunity_comments').insert({
    post_id: postId, user_id: user.id, parent_comment_id: parentId, content: checked.text,
  }).select().single()
  if (error) return json({ success: false, error: error.message }, 400)
  return json({ success: true, comment })
})
