import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'

// Read-only view of the admin audit log, for admins.
//
//   GET ?limit=50&before=<ISO timestamp>   newest first
//
// There is no write or delete route: entries are written by the functions that
// perform administrative actions, and the table refuses changes afterwards.

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'GET') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()
  const { data: profile, error: profileError } = await admin.from('users').select('role').eq('id', user.id).single()
  if (profileError || !hasPermission(profile?.role, 'view_audit_log')) {
    return json({ success: false, error: 'Admin access required' }, 403)
  }

  const url = new URL(req.url)
  const limit = Number(url.searchParams.get('limit') ?? 50)
  const beforeRaw = url.searchParams.get('before')
  const before = beforeRaw && !Number.isNaN(Date.parse(beforeRaw)) ? new Date(beforeRaw).toISOString() : null
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
    return json({ success: false, error: 'limit must be a whole number from 1 to 200.' }, 400)
  }

  const { data, error } = await admin.rpc('list_admin_audit_log', { p_limit: limit, p_before: before })
  if (error) return json({ success: false, error: error.message }, 500)
  return json({ success: true, entries: data }, 200)
})
