import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { banMessage } from './sanctions.ts'

// allowBanned: for the player's data rights (export, delete, privacy choices, abandoning a broken
// signup). A sanction limits what someone does in the game, never their rights over their own data.
export async function getVerifiedUser(req: Request, opts: { allowBanned?: boolean } = {}) {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return { user: null, error: 'Missing Authorization header' }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? Deno.env.get('PROJECT_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('PROJECT_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )

  const { data, error } = await supabase.auth.getUser()
  if (error || !data.user) return { user: null, error: 'Invalid or expired token' }

  // A banned player is refused by every function at once, with the reason, even while their
  // access token is still valid. (Sign-in and token refresh are blocked by the Auth ban the
  // sanctions function sets.) The text starts with "Account suspended" so the app can tell it
  // apart from an expired session.
  const banned = opts.allowBanned ? null : await banMessage(data.user.id)
  if (banned) return { user: null, error: banned }

  return { user: data.user, error: null }
}
