import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Inlined rather than imported from ../_shared — this function is deployed
// through the Supabase MCP tool, which (unlike the `supabase` CLI) doesn't
// resolve the project's cross-function `_shared/` relative imports. Every
// other function still uses `_shared/` as normal when deployed via the CLI.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

async function getVerifiedUser(req: Request) {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return { user: null, error: 'Missing Authorization header' }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? Deno.env.get('PROJECT_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('PROJECT_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )

  const { data, error } = await supabase.auth.getUser()
  if (error || !data.user) return { user: null, error: 'Invalid or expired token' }

  return { user: data.user, error: null }
}

function getAdminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? Deno.env.get('PROJECT_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('PROJECT_SERVICE_ROLE_KEY')!
  )
}

const PERMISSIONS = {
  moderate_posts: ['moderator', 'admin'],
  moderate_users: ['moderator', 'admin'],
  manage_roles: ['admin']
} as const
function hasPermission(role: string | null | undefined, permission: keyof typeof PERMISSIONS): boolean {
  return (PERMISSIONS[permission] as readonly string[]).includes(role ?? '')
}

const ALLOWED_STATUSES = ['reviewed', 'dismissed']

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
    .from('user_reports')
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
    p_action: 'report.resolve',
    p_target_type: 'user_report',
    p_target_id: reportId,
    p_metadata: { new_status: newStatus }
  })
  if (auditError) console.error('[resolve-report] audit failed:', auditError.message)

  return new Response(JSON.stringify({ success: true, report: updatedReport, audit_recorded: !auditError }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
