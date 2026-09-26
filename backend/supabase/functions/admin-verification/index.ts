import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'
import { recordAdminAction } from '../_shared/audit.ts'
import { isUuid } from '../_shared/validation.ts'
import { deleteEvidenceFiles } from '../_shared/verificationStorage.ts'
import { EVIDENCE_BUCKET, EVIDENCE_LINK_SECONDS, evidencePath } from '../_shared/verificationRules.ts'

// Admin review of coach applications (admins only; moderators are excluded
// pending the moderator-access review).
//
//   GET ?scope=pending|decided
//   POST { action: 'evidence', application_id }            5-minute links; the
//                                                          view is audited FIRST
//   POST { action: 'decide', application_id, decision: 'approved'|'rejected', reason }
//   POST { action: 'revoke', user_id, reason }
//   POST { action: 'delete_files', application_id }        retry a failed cleanup
//
// Decisions delete the evidence files immediately; the application record
// keeps each file's hash and size. The hash shows which file was reviewed, not
// that a certificate is genuine.

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1].charAt(0).toUpperCase() + match[1].slice(1) : raw
}

function cleanReason(raw: unknown): string | null {
  return typeof raw === 'string' && raw.trim() ? raw.trim().slice(0, 500) : null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'GET' && req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()
  const { data: profile, error: profileError } = await admin.from('users').select('role').eq('id', user.id).single()
  if (profileError || !hasPermission(profile?.role, 'review_verifications')) {
    return json({ success: false, error: 'Admin access required' }, 403)
  }

  if (req.method === 'GET') {
    const scope = new URL(req.url).searchParams.get('scope') === 'decided' ? 'decided' : 'pending'
    const { data, error } = await admin.rpc('admin_list_verification_applications', { p_scope: scope, p_limit: 50 })
    if (error) return json({ success: false, error: error.message }, 500)
    return json({ success: true, scope, applications: data })
  }

  const body = await req.json().catch(() => ({}))

  async function loadApplication(id: unknown) {
    if (!isUuid(id)) return { app: null, response: json({ success: false, error: 'A valid application_id is required.' }, 400) }
    const { data, error } = await admin.from('verification_applications')
      .select('id, user_id, status, evidence_count, files_deleted_at').eq('id', id).maybeSingle()
    if (error) return { app: null, response: json({ success: false, error: error.message }, 500) }
    if (!data) return { app: null, response: json({ success: false, error: 'Application not found.' }, 404) }
    return { app: data, response: null }
  }

  if (body.action === 'evidence') {
    const { app, response } = await loadApplication(body.application_id)
    if (!app) return response
    if (app.files_deleted_at || app.status !== 'pending') {
      return json({ success: false, error: 'The evidence files for this application have been deleted.' }, 410)
    }
    // Recorded BEFORE any link is issued. If the audit write fails, no link.
    const audited = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: 'verification.view_evidence',
      targetType: 'verification_application',
      targetId: app.id,
      metadata: { applicant_user_id: app.user_id, file_count: app.evidence_count, link_seconds: EVIDENCE_LINK_SECONDS }
    })
    if (!audited) return json({ success: false, error: 'Could not record this view, so the evidence was not opened.' }, 500)

    const paths = Array.from({ length: app.evidence_count }, (_, i) => evidencePath(app.user_id, app.id, i))
    const { data, error } = await admin.storage.from(EVIDENCE_BUCKET).createSignedUrls(paths, EVIDENCE_LINK_SECONDS)
    if (error) return json({ success: false, error: 'Could not open the evidence files.' }, 500)
    return json({
      success: true,
      expires_in_seconds: EVIDENCE_LINK_SECONDS,
      files: (data ?? []).map((f: { signedUrl: string | null; error: string | null }, i: number) => ({
        index: i + 1, url: f.signedUrl, error: f.error
      }))
    })
  }

  if (body.action === 'decide') {
    const decision = body.decision
    if (decision !== 'approved' && decision !== 'rejected') {
      return json({ success: false, error: 'decision must be approved or rejected.' }, 400)
    }
    const { app, response } = await loadApplication(body.application_id)
    if (!app) return response
    const reason = cleanReason(body.reason)
    const { data, error } = await admin.rpc('decide_verification_application', {
      p_application_id: app.id, p_admin_id: user.id, p_decision: decision, p_reason: reason
    })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 409)

    const filesDeleted = await deleteEvidenceFiles(admin, data)
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: decision === 'approved' ? 'verification.approve' : 'verification.reject',
      targetType: 'verification_application',
      targetId: app.id,
      metadata: { applicant_user_id: app.user_id, has_reason: reason !== null, files_deleted: filesDeleted }
    })
    return json({ success: true, status: data.status, files_deleted: filesDeleted, audit_recorded: auditRecorded })
  }

  if (body.action === 'revoke') {
    if (!isUuid(body.user_id)) return json({ success: false, error: 'A valid user_id is required.' }, 400)
    const reason = cleanReason(body.reason)
    const { data, error } = await admin.rpc('revoke_coach_status', {
      p_user_id: body.user_id, p_actor_id: user.id, p_by_self: false, p_reason: reason
    })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: 'verification.revoke',
      targetType: 'verification_application',
      targetId: data.application_id,
      metadata: { applicant_user_id: body.user_id }
    })
    return json({ success: true, status: data.status, audit_recorded: auditRecorded })
  }

  if (body.action === 'delete_files') {
    const { app, response } = await loadApplication(body.application_id)
    if (!app) return response
    if (app.status === 'pending') return json({ success: false, error: 'Decide the application first.' }, 409)
    if (app.files_deleted_at) return json({ success: true, files_deleted: true })
    const filesDeleted = await deleteEvidenceFiles(admin, {
      application_id: app.id, user_id: app.user_id, evidence_count: app.evidence_count
    })
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: 'verification.delete_files',
      targetType: 'verification_application',
      targetId: app.id,
      metadata: { applicant_user_id: app.user_id, files_deleted: filesDeleted }
    })
    return json({ success: filesDeleted, files_deleted: filesDeleted, audit_recorded: auditRecorded }, filesDeleted ? 200 : 500)
  }

  return json({ success: false, error: 'action must be evidence, decide, revoke or delete_files.' }, 400)
})
