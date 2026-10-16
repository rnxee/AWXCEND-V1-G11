import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// Change the amount (and optionally the meal) of one of your own meal logs. The nutrition is scaled
// in proportion: a 150 g log changed to 300 g doubles its calories and macros. Meals give no XP.
//
//   POST { meal_log_id, weight_g, meal_period? }

const PERIODS = ['Breakfast', 'Lunch', 'Dinner', 'Snack']
const SCALED = ['calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar']

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  if (!(await checkRateLimit(user.id, 'edit_meal', 60, 3600))) return rateLimitResponse(corsHeaders)

  const body = await req.json().catch(() => ({}))
  if (!isUuid(body.meal_log_id)) return json({ success: false, error: 'A valid meal_log_id is required.' }, 400)
  const grams = Number(body.weight_g)
  if (!Number.isFinite(grams) || grams <= 0 || grams > 5000) return json({ success: false, error: 'Amount must be between 1 and 5000 g.' }, 400)
  if (body.meal_period !== undefined && !PERIODS.includes(body.meal_period)) {
    return json({ success: false, error: `meal_period must be one of: ${PERIODS.join(', ')}` }, 400)
  }

  const admin = getAdminClient()
  const { data: meal } = await admin.from('fitrack_logs').select('*').eq('id', body.meal_log_id).eq('user_id', user.id).maybeSingle()
  if (!meal) return json({ success: false, error: 'Meal not found.' }, 404)  // same answer for "not yours"

  const ratio = grams / Number(meal.weight_g)
  const update: Record<string, unknown> = { weight_g: grams, updated_at: new Date().toISOString() }
  for (const k of SCALED) update[k] = Math.round(Number(meal[k]) * ratio * 100) / 100
  if (body.meal_period !== undefined) update.meal_period = body.meal_period

  const { error } = await admin.from('fitrack_logs').update(update).eq('id', body.meal_log_id).eq('user_id', user.id)
  if (error) return json({ success: false, error: 'That amount is too large for this food. Try a smaller one.' }, 400)
  return json({ success: true, meal: { ...meal, ...update } })
})
