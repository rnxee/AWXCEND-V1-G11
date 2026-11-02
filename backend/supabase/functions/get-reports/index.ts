import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'

const RESULT_LIMIT = 200
const ALLOWED_STATUS_FILTERS = ['pending', 'reviewed', 'dismissed']

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

  if (profileError || !hasPermission(profile?.role, 'moderate_users')) {
    return new Response(JSON.stringify({ success: false, error: 'Moderator access required' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const url = new URL(req.url)
  const statusFilter = url.searchParams.get('status') ?? 'pending'

  let dbQuery = admin
    .from('user_reports')
    .select(`
      id, reason, details, status, created_at, reviewed_at, context_type, context_excerpt,
      reporter:reporter_id ( id, username ),
      reported:reported_user_id ( id, username, role )
    `)
    .order('created_at', { ascending: false })
    .limit(RESULT_LIMIT)

  if (ALLOWED_STATUS_FILTERS.includes(statusFilter)) {
    dbQuery = dbQuery.eq('status', statusFilter)
  }

  const { data, error } = await dbQuery

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const reports = data ?? []
  const reportIds = reports.map(report => report.id)
  const { data: attachmentRows, error: attachmentError } = reportIds.length
    ? await admin.from('user_report_attachments')
      .select('user_report_id, original_name, mime_type, size_bytes, storage_path')
      .in('user_report_id', reportIds)
    : { data: [], error: null }
  if (attachmentError) {
    return new Response(JSON.stringify({ success: false, error: attachmentError.message }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  const paths = (attachmentRows ?? []).map(row => row.storage_path)
  const { data: signed } = paths.length
    ? await admin.storage.from('bug-report-evidence').createSignedUrls(paths, 3600)
    : { data: [] }
  const signedByPath = new Map((signed ?? []).map(item => [item.path, item.signedUrl]))
  const byReport = new Map<string, unknown[]>()
  for (const row of attachmentRows ?? []) {
    const list = byReport.get(row.user_report_id) ?? []
    list.push({ original_name: row.original_name, mime_type: row.mime_type, size_bytes: row.size_bytes,
      signed_url: signedByPath.get(row.storage_path) ?? null })
    byReport.set(row.user_report_id, list)
  }
  const withAttachments = reports.map(report => ({ ...report, attachments: byReport.get(report.id) ?? [] }))
  return new Response(JSON.stringify({ success: true, reports: withAttachments }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
