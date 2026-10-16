import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// A player deletes one of their own meal logs (fitrack_logs).
//
//   POST { meal_log_id }
//
// Meals give no XP. The daily meal gold stays: it is keyed to the game day, so deleting and
// re-logging can't earn it twice.

const RL_MAX = 60
const RL_WINDOW_SECONDS = 3600

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  if (!(await checkRateLimit(user.id, 'delete_meal', RL_MAX, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)

  const body = await req.json().catch(() => ({}))
  if (!isUuid(body.meal_log_id)) return json({ success: false, error: 'A valid meal_log_id is required.' }, 400)

  // Same answer for "not found" and "not yours": no probing other players' meals.
  const { data, error } = await getAdminClient().from('fitrack_logs').delete()
    .eq('id', body.meal_log_id).eq('user_id', user.id).select('id')
  if (error) return json({ success: false, error: 'Could not delete the meal.' }, 500)
  if (!data || data.length === 0) return json({ success: false, error: 'Meal not found.' }, 404)
  return json({ success: true, deleted: body.meal_log_id })
})
