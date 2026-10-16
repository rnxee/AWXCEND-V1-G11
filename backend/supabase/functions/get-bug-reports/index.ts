import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'

const RESULT_LIMIT = 200
const ALLOWED_STATUS_FILTERS = ['open', 'resolved', 'dismissed']

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

  const url = new URL(req.url)
  const statusFilter = url.searchParams.get('status') ?? 'open'

  let dbQuery = admin
    .from('bug_reports')
    .select(`
      id, category, description, status, created_at, reviewed_at,
      reporter:user_id ( id, username )
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
