import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { consentRequiredResponse } from '../_shared/consent.ts'
import { deleteEvidenceFiles } from '../_shared/verificationStorage.ts'
import {
  EVIDENCE_BUCKET,
  MAX_EVIDENCE_FILES,
  decodeJpegBase64,
  evidencePath,
  sha256Hex,
  trainingHistoryStatus,
  validateSummary
} from '../_shared/verificationRules.ts'
import { isUuid } from '../_shared/validation.ts'

// The caller's own verification.
//
//   GET                                          training-history counts, coach
//                                                applications, whether they can apply
//   POST { action: 'apply', experience_summary, images: [base64 JPEG], notice_version }
//   POST { action: 'withdraw', application_id }  files are deleted right away
//   POST { action: 'remove_coach_status' }
//
// Consistent training history is an activity signal from GymApp logs, not
// evidence of experience. Coach evidence goes to a PRIVATE bucket only the
// server can reach, and is deleted as soon as the application is decided or
// withdrawn. Nothing here reads or writes form_verified.

const RL_MAX = 20
const RL_WINDOW_SECONDS = 3600

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

function errorCode(raw: string): string | undefined {
  return raw.match(/^([A-Z_]+):/)?.[1]
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'GET' && req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()

  if (req.method === 'GET') {
    const [mine, consent] = await Promise.all([
      admin.rpc('get_my_verification', { p_user_id: user.id }),
      admin.rpc('has_current_consent', { p_user_id: user.id, p_consent_type: 'verification' })
    ])
    if (mine.error) return json({ success: false, error: mine.error.message }, 500)
    return json({
      success: true,
      training_history: trainingHistoryStatus(mine.data.training_history),
      coach: {
        applications: mine.data.applications,
        block: mine.data.coach_block,
        notice_acknowledged: consent.data === true
      }
    })
  }

  if (!(await checkRateLimit(user.id, 'verification', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))

  if (body.action === 'apply') {
    const consentBlock = await consentRequiredResponse(user.id, 'verification', corsHeaders)
    if (consentBlock) return consentBlock

    const { summary, error: summaryError } = validateSummary(body.experience_summary)
    if (summaryError) return json({ success: false, error: summaryError }, 400)
    const images = Array.isArray(body.images) ? body.images : []
    if (images.length < 1 || images.length > MAX_EVIDENCE_FILES) {
      return json({ success: false, error: `Attach 1 to ${MAX_EVIDENCE_FILES} images.` }, 400)
    }
    if (typeof body.notice_version !== 'string') return json({ success: false, error: 'notice_version is required.' }, 400)

    const files: Uint8Array[] = []
    for (const raw of images) {
      const { bytes, error } = decodeJpegBase64(raw)
      if (error) return json({ success: false, error }, 400)
      files.push(bytes as Uint8Array)
    }

    // Refuse early (pending application, already verified, cooldown) before
    // any file is uploaded. The insert below re-checks, so a race still fails.
    const { data: block } = await admin.rpc('coach_application_block', { p_user_id: user.id })
    if (block) {
      const message = block.code === 'APPLICATION_PENDING' ? 'You already have an application waiting for review.'
        : block.code === 'ALREADY_VERIFIED' ? 'You are already a verified coach.'
        : 'You can apply again 7 days after a rejection.'
      return json({ success: false, code: block.code, until: block.until ?? null, error: message }, 409)
    }

    const applicationId = crypto.randomUUID()
    const hashes = await Promise.all(files.map((f) => sha256Hex(f)))
    const uploaded: string[] = []
    const cleanup = async () => {
      if (uploaded.length) await admin.storage.from(EVIDENCE_BUCKET).remove(uploaded)
    }

    for (let i = 0; i < files.length; i++) {
      const path = evidencePath(user.id, applicationId, i)
      const { error } = await admin.storage.from(EVIDENCE_BUCKET).upload(path, files[i], { contentType: 'image/jpeg', upsert: false })
      if (error) {
        await cleanup()
        console.error('[verification] upload failed:', error.message)
        return json({ success: false, error: 'Could not upload your images. Nothing was submitted; please try again.' }, 500)
      }
      uploaded.push(path)
    }

    const { data, error } = await admin.rpc('begin_coach_application', {
      p_application_id: applicationId,
      p_user_id: user.id,
      p_summary: summary,
      p_hashes: hashes,
      p_sizes: files.map((f) => f.length),
      p_notice_version: body.notice_version
    })
    if (error) {
      await cleanup()
      const code = errorCode(error.message)
      const status = code === 'CONSENT_REQUIRED' ? 403 : code ? 409 : 500
      return json({ success: false, code, error: playerMessage(error.message) }, status)
    }
    return json({ success: true, application: data })
  }

  if (body.action === 'withdraw') {
    if (!isUuid(body.application_id)) return json({ success: false, error: 'A valid application_id is required.' }, 400)
    const { data, error } = await admin.rpc('withdraw_verification_application', {
      p_application_id: body.application_id, p_user_id: user.id
    })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
    const filesDeleted = await deleteEvidenceFiles(admin, data)
    return json({ success: true, status: data.status, files_deleted: filesDeleted })
  }

  if (body.action === 'remove_coach_status') {
    const { data, error } = await admin.rpc('revoke_coach_status', {
      p_user_id: user.id, p_actor_id: user.id, p_by_self: true, p_reason: null
    })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
    return json({ success: true, status: data.status })
  }

  return json({ success: false, error: 'action must be apply, withdraw or remove_coach_status.' }, 400)
})
