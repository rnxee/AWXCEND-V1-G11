import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { isUuid } from '../_shared/validation.ts'
import { excerptOf } from '../_shared/paging.ts'

// Optional: { message_type: 'chat' | 'dm', message_id } reports one message.
// The client sends only the id; the message is looked up here, must have been
// sent by the reported user (and, for a DM, sent to the reporter), and a copy
// of its text is stored with the report so a moderator can still read it if
// the message is removed, and nobody can put words in someone else's mouth.
const MESSAGE_TYPES = ['chat', 'dm']

const ALLOWED_REASONS = ['harassment', 'spam', 'impersonation', 'inappropriate_content', 'cheating', 'other']
const MAX_DETAILS_LENGTH = 500

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

  if (!(await checkRateLimit(user.id, 'report_user', 10, 3600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const reportedUserId = typeof body.reported_user_id === 'string' ? body.reported_user_id.trim() : ''
  const reason = typeof body.reason === 'string' ? body.reason.trim() : ''
  const details = typeof body.details === 'string' ? body.details.trim().slice(0, MAX_DETAILS_LENGTH) : ''
  const messageType = body.message_type ?? null
  const messageId = body.message_id ?? null

  const errors: string[] = []
  if (!reportedUserId) errors.push('reported_user_id is required')
  if (reportedUserId === user.id) errors.push('You cannot report yourself')
  if (!ALLOWED_REASONS.includes(reason)) errors.push(`reason must be one of: ${ALLOWED_REASONS.join(', ')}`)
  if (messageType !== null || messageId !== null) {
    if (!MESSAGE_TYPES.includes(messageType)) errors.push(`message_type must be one of: ${MESSAGE_TYPES.join(', ')}`)
    if (!isUuid(messageId)) errors.push('message_id must be a valid id')
  }

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const { data: targetUser } = await admin
    .from('users')
    .select('id')
    .eq('id', reportedUserId)
    .single()

  if (!targetUser) {
    return new Response(JSON.stringify({ success: false, error: 'User not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  let context: { context_type: string; context_id: string; context_excerpt: string } | null = null
  if (messageType) {
    const found = messageType === 'chat'
      ? await admin.from('chat_messages').select('user_id, message').eq('id', messageId).maybeSingle()
      : await admin.from('direct_messages').select('sender_id, recipient_id, message').eq('id', messageId).maybeSingle()
    const msg = found.data as Record<string, string> | null
    const sender = msg ? (messageType === 'chat' ? msg.user_id : msg.sender_id) : null
    const allowed = msg && sender === reportedUserId && (messageType === 'chat' || msg.recipient_id === user.id)
    if (!allowed) {
      return new Response(JSON.stringify({ success: false, error: 'That message could not be found.' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    context = { context_type: messageType, context_id: messageId, context_excerpt: excerptOf(msg.message) }
  }

  const { data: report, error: insertError } = await admin
    .from('user_reports')
    .insert({
      reporter_id: user.id,
      reported_user_id: reportedUserId,
      reason,
      details: details || null,
      ...(context ?? {})
    })
    .select()
    .single()

  if (insertError) {
    return new Response(JSON.stringify({ success: false, error: insertError.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, report }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
