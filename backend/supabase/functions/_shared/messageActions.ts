import { corsHeaders } from './cors.ts'
import { getVerifiedUser } from './auth.ts'
import { getAdminClient } from './supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from './rateLimit.ts'
import { restrictionResponse } from './sanctions.ts'
import { canEdit, checkMessage, EDIT_WINDOW_MINUTES } from './messageRules.ts'
import { isUuid } from './validation.ts'

// Edit or delete your own chat message or direct message. One body: POST { action: 'edit'|'delete', id, message? }.
// Edit: within 15 minutes, same text rules as sending, and it respects a restriction (someone muted can't
// rewrite old messages into new ones). Delete: any time, and allowed under a restriction. A DM is
// removed for both people.

type Target = { table: string; ownerColumn: string; rateAction: string; privilege: 'chat' | 'dm'; maxLength: number }

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

export async function handle(req: Request, t: Target): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  if (!(await checkRateLimit(user.id, t.rateAction, 60, 300))) return rateLimitResponse(corsHeaders)

  const body = await req.json().catch(() => ({}))
  if (body.action !== 'edit' && body.action !== 'delete') return json({ success: false, error: 'action must be edit or delete.' }, 400)
  if (!isUuid(body.id)) return json({ success: false, error: 'A valid id is required.' }, 400)

  const admin = getAdminClient()
  // The same answer for "not found" and "not yours": no probing other people's messages.
  const { data: row } = await admin.from(t.table).select('id, created_at').eq('id', body.id).eq(t.ownerColumn, user.id).maybeSingle()
  if (!row) return json({ success: false, error: 'Message not found.' }, 404)

  if (body.action === 'delete') {
    const { error } = await admin.from(t.table).delete().eq('id', body.id).eq(t.ownerColumn, user.id)
    if (error) return json({ success: false, error: 'Could not delete the message.' }, 500)
    return json({ success: true, deleted: body.id })
  }

  const restricted = await restrictionResponse(user.id, t.privilege, corsHeaders)
  if (restricted) return restricted
  if (!canEdit(row.created_at)) {
    return json({ success: false, error: `Messages can only be edited for ${EDIT_WINDOW_MINUTES} minutes after sending.` }, 409)
  }
  const { text, error } = checkMessage(body.message, t.maxLength)
  if (error) return json({ success: false, errors: [error] }, 400)

  const { error: updateError } = await admin.from(t.table)
    .update({ message: text, edited_at: new Date().toISOString() }).eq('id', body.id).eq(t.ownerColumn, user.id)
  if (updateError) return json({ success: false, error: 'Could not edit the message.' }, 500)
  return json({ success: true, id: body.id, message: text })
}
