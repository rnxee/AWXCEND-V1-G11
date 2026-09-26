import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { EVIDENCE_BUCKET, evidencePath } from '../_shared/verificationRules.ts'

// Permanently deletes the caller's own account.
//
// Three checks stand between a request and an irreversible delete, each
// closing a different hole:
//
//  1. The typed username must match. Guards against a mis-tap: nobody
//     deletes an account by accident when they have to spell it out.
//
//  2. The PASSWORD is re-verified here, server-side. A session token alone is
//     not enough to destroy an account — a token left on a shared device, or
//     lifted from one, would otherwise be a one-request wipe. Checking it in
//     the client would be decoration: anyone holding the token could call
//     this endpoint directly and skip the UI.
//
//  3. The last admin cannot delete themselves, or nobody would be left able
//     to moderate the app.
//
// What happens to the data is decided by the foreign keys (see migration
// 20260910160000): the user's own content cascades away, while moderation
// and audit records survive with the user anonymised.

// Tight on purpose: this endpoint verifies a password, so without a limit it
// would double as an unthrottled password-guessing oracle for anyone holding
// a stolen session token.
const RL_MAX = 5
const RL_WINDOW_SECONDS = 3600

const IMAGE_BUCKET = 'gymmunity-images'
const LIST_PAGE = 1000

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

  if (!(await checkRateLimit(user.id, 'delete_account', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const password = typeof body.password === 'string' ? body.password : ''
  const confirmUsername = typeof body.confirm_username === 'string' ? body.confirm_username.trim() : ''

  if (!password || !confirmUsername) {
    return json({ success: false, errors: ['Enter your username and password to confirm.'] }, 400)
  }

  const admin = getAdminClient()

  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('username, role')
    .eq('id', user.id)
    .maybeSingle()

  if (profileError) return json({ success: false, error: profileError.message }, 400)
  if (!profile) return json({ success: false, errors: ['Account not found.'] }, 404)

  // Exact match, matching the client-side gate: usernames are case-sensitive
  // everywhere else in the app, so a looser check here would be the one
  // place they were not.
  if (confirmUsername !== profile.username) {
    return json({ success: false, errors: ["The username you typed doesn't match this account."] }, 400)
  }

  if (profile.role === 'admin') {
    const { count } = await admin
      .from('users')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'admin')

    if ((count ?? 0) <= 1) {
      return json({
        success: false,
        errors: ["You're the only admin. Promote another admin before deleting this account, or nobody will be able to moderate the app."]
      }, 409)
    }
  }

  if (!user.email) {
    return json({ success: false, errors: ['This account has no email address to verify the password against.'] }, 400)
  }

  // A throwaway anon client whose only job is to check the password. Nothing
  // it signs in with is persisted or returned; the session it creates is
  // removed along with the account a moment later.
  const verifier = createClient(
    Deno.env.get('SUPABASE_URL') ?? Deno.env.get('PROJECT_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('PROJECT_ANON_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
  )
  const { error: passwordError } = await verifier.auth.signInWithPassword({
    email: user.email,
    password
  })
  if (passwordError) {
    return json({ success: false, errors: ['Incorrect password.'] }, 401)
  }

  // Uploaded images go first, and a failure here ABORTS the deletion. Post
  // rows cascade with the account, so if the account were deleted anyway the
  // images would be left publicly reachable with nothing pointing at them and
  // no owner left to ask for their removal. Uploads live under `${user.id}/`
  // (see create-post).
  for (;;) {
    const { data: files, error: listError } = await admin.storage
      .from(IMAGE_BUCKET)
      .list(user.id, { limit: LIST_PAGE })

    if (listError) {
      return json({ success: false, error: 'Could not remove your uploaded images, so nothing was deleted. Please try again.' }, 500)
    }
    if (!files || files.length === 0) break

    const { error: removeError } = await admin.storage
      .from(IMAGE_BUCKET)
      .remove(files.map((f) => `${user.id}/${f.name}`))

    if (removeError) {
      return json({ success: false, error: 'Could not remove your uploaded images, so nothing was deleted. Please try again.' }, 500)
    }
    if (files.length < LIST_PAGE) break
  }

  // Coach verification evidence lives in a PRIVATE bucket, under paths known
  // from each application that still has files. Same rule as the images above:
  // if it can't be removed, nothing is deleted.
  const { data: pendingEvidence, error: evidenceError } = await admin
    .from('verification_applications')
    .select('id, evidence_count')
    .eq('user_id', user.id)
    .is('files_deleted_at', null)
  if (evidenceError) {
    return json({ success: false, error: 'Could not remove your verification documents, so nothing was deleted. Please try again.' }, 500)
  }
  const evidencePaths = (pendingEvidence ?? []).flatMap((a) =>
    Array.from({ length: a.evidence_count }, (_, i) => evidencePath(user.id, a.id, i)))
  if (evidencePaths.length > 0) {
    const { error: removeEvidenceError } = await admin.storage.from(EVIDENCE_BUCKET).remove(evidencePaths)
    if (removeEvidenceError) {
      return json({ success: false, error: 'Could not remove your verification documents, so nothing was deleted. Please try again.' }, 500)
    }
  }

  // rate_limits has no foreign key to users (its rows are short-lived), so
  // the cascade would not reach it.
  await admin.from('rate_limits').delete().eq('user_id', user.id)

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
  if (deleteError) {
    return json({ success: false, error: `Could not delete the account: ${deleteError.message}` }, 500)
  }

  return json({ success: true }, 200)
})
