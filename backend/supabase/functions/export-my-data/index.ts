import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { gameDay } from '../_shared/gameDay.ts'

// Downloads a copy of the caller's own data as JSON.
//
// The account id comes only from the verified token — never from the request —
// so there is no way to ask for someone else's export. What is included and
// what is deliberately excluded (with reasons) is defined in the database
// (export_user_data and privacy_export_coverage), and the file says so.

// Exports are large reads; a few per hour is plenty for a person.
const RL_MAX = 5
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
  if (req.method !== 'GET') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  if (!(await checkRateLimit(user.id, 'export_my_data', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders, 'You can download your data a few times an hour. Try again later.')
  }

  const { data, error } = await getAdminClient().rpc('export_user_data', { p_user_id: user.id })
  if (error) return json({ success: false, error: 'Could not prepare your data. Try again.' }, 500)

  return new Response(JSON.stringify(data, null, 2), {
    status: 200,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Content-Disposition': `attachment; filename="awxcend-my-data-${gameDay()}.json"`,
      'Cache-Control': 'no-store'
    }
  })
})
