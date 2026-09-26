import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { abandonDecision } from '../_shared/signupRules.ts'

// Removes a half-created signup: the auth login signUp() just made, when
// /register then refused to create its profile (a taken username, most often).
//
// Without this, the client could only sign out, the login stayed behind, and
// that email was locked out of signing up ever again.
//
// It can delete exactly one account — the caller's own, proven by the session
// token — and only while that account has no profile row and is minutes old
// (see abandonDecision). A finished account always has a profile row, so this
// path cannot reach one. Every doubt refuses: a failed profile lookup is
// treated as "a profile may exist", never as "none".
//
// No rate limit on purpose: the only account it can touch is the caller's own
// brand-new one, and once deleted there is nothing left to call it with.
//
// public.users.id references auth.users ON DELETE CASCADE, so even if
// /register's insert were still landing at the moment of the delete, no half
// account could survive it.

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

  const admin = getAdminClient()

  const { data: profile, error: lookupError } = await admin
    .from('users')
    .select('id')
    .eq('id', user.id)
    .maybeSingle()
  if (lookupError) {
    // Fail closed: if we cannot confirm there is no profile, do not delete.
    return json({ success: false, error: 'Could not check the account. Nothing was deleted.' }, 500)
  }

  const decision = abandonDecision({
    profileExists: Boolean(profile),
    createdAt: user.created_at,
    now: Date.now()
  })
  if (!decision.allowed) {
    return json({ success: false, code: decision.code, error: 'This account cannot be removed this way.' }, 409)
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
  if (deleteError) {
    return json({ success: false, error: 'Could not remove the unfinished signup.' }, 500)
  }

  return json({ success: true }, 200)
})
