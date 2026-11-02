import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

const ALLOWED_CATEGORIES = ['bug', 'feature_request', 'other']
const MAX_DESCRIPTION_LENGTH = 1000
const MAX_ATTACHMENTS = 5
const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024
const ATTACHMENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])

type AttachmentInput = { name: string; mime_type: string; data_base64: string }

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
  if (!user) {
    return json({ success: false, error: authError }, 401)
  }

  if (!(await checkRateLimit(user.id, 'report_bug', 10, 3600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const category = typeof body.category === 'string' ? body.category.trim() : 'bug'
  const description = typeof body.description === 'string' ? body.description.trim() : ''

  const errors: string[] = []
  if (!ALLOWED_CATEGORIES.includes(category)) errors.push(`category must be one of: ${ALLOWED_CATEGORIES.join(', ')}`)
  if (!description) errors.push('description is required')
  if (description.length > MAX_DESCRIPTION_LENGTH) errors.push(`description must be at most ${MAX_DESCRIPTION_LENGTH} characters`)

  if (errors.length > 0) {
    return json({ success: false, errors }, 400)
  }

  const admin = getAdminClient()

  const rawAttachments = body.attachments === undefined ? [] : body.attachments
  if (!Array.isArray(rawAttachments) || rawAttachments.length > MAX_ATTACHMENTS) {
    return json({ success: false, error: `attachments must contain at most ${MAX_ATTACHMENTS} files` }, 400)
  }
  const attachments: { name: string; mime_type: string; bytes: Uint8Array }[] = []
  for (const item of rawAttachments as unknown[]) {
    const a = item as Partial<AttachmentInput> | null
    const name = typeof a?.name === 'string' ? a.name.trim().slice(0, 255) : ''
    const mime = typeof a?.mime_type === 'string' ? a.mime_type.trim().toLowerCase() : ''
    const bytes = typeof a?.data_base64 === 'string' ? bytesFor(a.data_base64) : null
    if (!name || !ATTACHMENT_TYPES.has(mime) || !bytes || bytes.length > MAX_ATTACHMENT_BYTES || !matchesSignature(bytes, mime)) {
      return json({ success: false, error: 'Each attachment must be a valid JPG, PNG, WEBP, or PDF no larger than 5 MB.' }, 400)
    }
    attachments.push({ name, mime_type: mime, bytes })
  }

  const { data: report, error: insertError } = await admin
    .from('bug_reports')
    .insert({
      user_id: user.id,
      category,
      description
    })
    .select()
    .single()

  if (insertError) {
    return json({ success: false, error: insertError.message }, 400)
  }

  const uploadedPaths: string[] = []
  try {
    for (const attachment of attachments) {
      const path = `${user.id}/${report.id}/${crypto.randomUUID()}.${extensionFor(attachment.mime_type)}`
      const { error: uploadError } = await admin.storage.from('bug-report-evidence').upload(path, attachment.bytes, {
        contentType: attachment.mime_type,
        upsert: false,
      })
      if (uploadError) throw new Error(`Attachment upload failed: ${uploadError.message}`)
      uploadedPaths.push(path)
      const { error: rowError } = await admin.from('bug_report_attachments').insert({
        bug_report_id: report.id,
        user_id: user.id,
        original_name: attachment.name,
        storage_path: path,
        mime_type: attachment.mime_type,
        size_bytes: attachment.bytes.length,
      })
      if (rowError) throw new Error(`Attachment record failed: ${rowError.message}`)
    }
  } catch (error) {
    if (uploadedPaths.length) await admin.storage.from('bug-report-evidence').remove(uploadedPaths)
    await admin.from('bug_reports').delete().eq('id', report.id).eq('user_id', user.id)
    return json({ success: false, error: error instanceof Error ? error.message : 'Attachment upload failed' }, 400)
  }

  return json({ success: true, report, attachments: attachments.map(a => ({ name: a.name, mime_type: a.mime_type,
    size_bytes: a.bytes.length })) })
})
