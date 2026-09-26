import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'

// Deactivates or reactivates the caller's own account.
//
// Deactivation hides the account from every other user and deletes nothing,
// so it needs no password: the worst a stolen session can do with it is hide
// the account, which the owner undoes by logging in. Deletion is the
// destructive path, and that one does re-verify the password.
//
// Only ever touches the caller's own row. There is no user_id in the body to
// get wrong or to forge.

const RL_MAX = 10
const RL_WINDOW_SECONDS = 3600

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
  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  if (!(await checkRateLimit(user.id, 'set_account_active', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  if (typeof body.active !== 'boolean') {
    return json({ success: false, errors: ['active must be true or false'] }, 400)
  }

  const admin = getAdminClient()

  const { data, error } = await admin
    .from('users')
    .update({ deactivated_at: body.active ? null : new Date().toISOString() })
    .eq('id', user.id)
    .select('deactivated_at')
    .maybeSingle()

  if (error) return json({ success: false, error: error.message }, 400)
  if (!data) return json({ success: false, errors: ['Account not found.'] }, 404)

  return json({ success: true, active: data.deactivated_at === null, deactivated_at: data.deactivated_at }, 200)
})
