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
  manage_bug_reports: ['moderator', 'admin'],
  manage_roles: ['admin']
} as const
function hasPermission(role: string | null | undefined, permission: keyof typeof PERMISSIONS): boolean {
  return (PERMISSIONS[permission] as readonly string[]).includes(role ?? '')
}

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
