import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { cleanText, isUuid } from '../_shared/validation.ts'
import { excerptOf } from '../_shared/paging.ts'
import { restrictionResponse } from '../_shared/sanctions.ts'

// Optional: { message_type: 'chat' | 'dm', message_id } reports one message.
// The client sends only the id; the message is looked up here, must have been
// sent by the reported user (and, for a DM, sent to the reporter), and a copy
// of its text is stored with the report so a moderator can still read it if
// the message is removed, and nobody can put words in someone else's mouth.
const MESSAGE_TYPES = ['chat', 'dm']

const ALLOWED_REASONS = ['harassment', 'spam', 'impersonation', 'inappropriate_content', 'cheating', 'other']
const MAX_DETAILS_LENGTH = 500
const MAX_ATTACHMENTS = 5
const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024
const ATTACHMENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])

function bytesFor(raw: string): Uint8Array | null {
  try {
    const bytes = Uint8Array.from(atob(raw), c => c.charCodeAt(0))
    return bytes.length ? bytes : null
  } catch {
    return null
  }
}

function matchesSignature(bytes: Uint8Array, mime: string): boolean {
  if (mime === 'image/jpeg') return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
  if (mime === 'image/png') return bytes.length >= 8 && bytes.slice(0, 8).every((b, i) => b === [137, 80, 78, 71, 13, 10, 26, 10][i])
  if (mime === 'image/webp') return bytes.length >= 12 && new TextDecoder().decode(bytes.slice(0, 4)) === 'RIFF' &&
    new TextDecoder().decode(bytes.slice(8, 12)) === 'WEBP'
  if (mime === 'application/pdf') return new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-'
  return false
}

function extensionFor(mime: string): string {
  return ({ 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' } as Record<string, string>)[mime]
}

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
  const restricted = await restrictionResponse(user.id, 'report', corsHeaders)
  if (restricted) return restricted

  const body = await req.json().catch(() => ({}))
  const reportedUserId = typeof body.reported_user_id === 'string' ? body.reported_user_id.trim() : ''
  const reason = typeof body.reason === 'string' ? body.reason.trim() : ''
  const details = cleanText(body.details).slice(0, MAX_DETAILS_LENGTH)
  const messageType = body.message_type ?? null
  const messageId = body.message_id ?? null
  const rawAttachments = body.attachments === undefined ? [] : body.attachments

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

  if (!Array.isArray(rawAttachments) || rawAttachments.length > MAX_ATTACHMENTS) {
    return new Response(JSON.stringify({ success: false, error: `attachments must contain at most ${MAX_ATTACHMENTS} files` }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  const attachments: { name: string; mime_type: string; bytes: Uint8Array }[] = []
  for (const item of rawAttachments as unknown[]) {
    const a = item as { name?: unknown; mime_type?: unknown; data_base64?: unknown } | null
    const name = typeof a?.name === 'string' ? a.name.trim().slice(0, 255) : ''
    const mime = typeof a?.mime_type === 'string' ? a.mime_type.trim().toLowerCase() : ''
    const bytes = typeof a?.data_base64 === 'string' ? bytesFor(a.data_base64) : null
    if (!name || !ATTACHMENT_TYPES.has(mime) || !bytes || bytes.length > MAX_ATTACHMENT_BYTES || !matchesSignature(bytes, mime)) {
      return new Response(JSON.stringify({ success: false, error: 'Each attachment must be a valid JPG, PNG, WEBP, or PDF no larger than 5 MB.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    attachments.push({ name, mime_type: mime, bytes })
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

  const uploadedPaths: string[] = []
  try {
    for (const attachment of attachments) {
      const path = `${user.id}/user-report-${report.id}/${crypto.randomUUID()}.${extensionFor(attachment.mime_type)}`
      const { error: uploadError } = await admin.storage.from('bug-report-evidence').upload(path, attachment.bytes, {
        contentType: attachment.mime_type, upsert: false,
      })
      if (uploadError) throw new Error(`Attachment upload failed: ${uploadError.message}`)
      uploadedPaths.push(path)
      const { error: rowError } = await admin.from('user_report_attachments').insert({
        user_report_id: report.id, user_id: user.id, original_name: attachment.name,
        storage_path: path, mime_type: attachment.mime_type, size_bytes: attachment.bytes.length,
      })
      if (rowError) throw new Error(`Attachment record failed: ${rowError.message}`)
    }
  } catch (error) {
    if (uploadedPaths.length) await admin.storage.from('bug-report-evidence').remove(uploadedPaths)
    await admin.from('user_reports').delete().eq('id', report.id).eq('reporter_id', user.id)
    return new Response(JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Attachment upload failed' }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  return new Response(JSON.stringify({ success: true, report }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
