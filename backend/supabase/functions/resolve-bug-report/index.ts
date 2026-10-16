import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'

const ALLOWED_STATUSES = ['resolved', 'dismissed']

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

  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profileError || !hasPermission(profile?.role, 'manage_bug_reports')) {
    return new Response(JSON.stringify({ success: false, error: 'Moderator access required' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const body = await req.json().catch(() => ({}))
  const reportId = typeof body.report_id === 'string' ? body.report_id.trim() : ''
  const newStatus = typeof body.status === 'string' ? body.status.trim() : ''

  const errors: string[] = []
  if (!reportId) errors.push('report_id is required')
  if (!ALLOWED_STATUSES.includes(newStatus)) errors.push(`status must be one of: ${ALLOWED_STATUSES.join(', ')}`)

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data: updatedReport, error: updateError } = await admin
    .from('bug_reports')
    .update({ status: newStatus, reviewed_by: user.id, reviewed_at: new Date().toISOString() })
    .eq('id', reportId)
    .select()
    .single()

  if (updateError || !updatedReport) {
    return new Response(JSON.stringify({ success: false, error: updateError?.message || 'Report not found' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Append-only audit entry (see migration 20260917160000). Written after the
  // change succeeds; a failed write is reported, not hidden.
  const { error: auditError } = await admin.rpc('record_admin_action', {
    p_actor_user_id: user.id,
    p_action: 'bug_report.resolve',
    p_target_type: 'bug_report',
    p_target_id: reportId,
    p_metadata: { new_status: newStatus }
  })
  if (auditError) console.error('[resolve-bug-report] audit failed:', auditError.message)

  return new Response(JSON.stringify({ success: true, report: updatedReport, audit_recorded: !auditError }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
