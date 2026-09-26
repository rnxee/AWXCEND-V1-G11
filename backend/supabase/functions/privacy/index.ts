import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'

// Privacy notices and the user's acknowledgements.
//
//   GET  (no login)   the current notices, so signup can show them
//   GET  (logged in)  current notices + the user's latest decision per notice,
//                     their full history, and the relative-leaderboard choice
//   POST { action: 'acknowledge', consent_type, notice_version }
//   POST { action: 'set_relative_leaderboard', opt_in, notice_version }
//
// Records are append-only (trigger-enforced). The notice text is served from
// the database, so what a user saw and what they acknowledged are the same
// stored version. Notices are DRAFTS pending review; publishing a new version
// is a migration.

const RL_MAX = 30
const RL_WINDOW_SECONDS = 300
const ACK_TYPES = ['privacy_notice', 'camera', 'gps', 'ai_features', 'verification']
const VERSION_RE = /^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[a-z0-9-]+$/

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const admin = getAdminClient()
  const { user } = await getVerifiedUser(req)

  if (req.method === 'GET') {
    if (!user) {
      const { data, error } = await admin.rpc('get_current_notices')
      if (error) return json({ success: false, error: error.message }, 500)
      return json({ success: true, notices: data })
    }
    const { data, error } = await admin.rpc('get_privacy_status', { p_user_id: user.id })
    if (error) return json({ success: false, error: error.message }, 500)
    return json({ success: true, ...data })
  }

  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)
  if (!user) return json({ success: false, error: 'Invalid or expired token' }, 401)

  if (!(await checkRateLimit(user.id, 'privacy', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const version = typeof body.notice_version === 'string' ? body.notice_version : null
  if (version !== null && !VERSION_RE.test(version)) {
    return json({ success: false, error: 'notice_version is not valid.' }, 400)
  }

  if (body.action === 'acknowledge') {
    if (!ACK_TYPES.includes(body.consent_type)) {
      return json({ success: false, error: `consent_type must be one of: ${ACK_TYPES.join(', ')}.` }, 400)
    }
    if (!version) return json({ success: false, error: 'notice_version is required.' }, 400)
    const { data, error } = await admin.rpc('record_consent', {
      p_user_id: user.id, p_consent_type: body.consent_type, p_notice_version: version
    })
    if (error) {
      const status = /NOTICE_VERSION_OUTDATED|INVALID_CONSENT_TYPE/.test(error.message) ? 409 : 500
      return json({ success: false, code: status === 409 ? 'NOTICE_VERSION_OUTDATED' : undefined, error: playerMessage(error.message) }, status)
    }
    return json({ success: true, consent: data })
  }

  if (body.action === 'set_relative_leaderboard') {
    if (typeof body.opt_in !== 'boolean') return json({ success: false, error: 'opt_in must be true or false.' }, 400)
    if (body.opt_in && !version) return json({ success: false, error: 'notice_version is required to join.' }, 400)
    const { data, error } = await admin.rpc('set_relative_leaderboard', {
      p_user_id: user.id, p_opt_in: body.opt_in, p_notice_version: version
    })
    if (error) {
      const status = /NOTICE_VERSION_OUTDATED/.test(error.message) ? 409 : 500
      return json({ success: false, code: status === 409 ? 'NOTICE_VERSION_OUTDATED' : undefined, error: playerMessage(error.message) }, status)
    }
    return json({ success: true, choice: data })
  }

  return json({ success: false, error: 'action must be acknowledge or set_relative_leaderboard.' }, 400)
})
