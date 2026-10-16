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

  return new Response(JSON.stringify({ success: true, reports: data ?? [] }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
