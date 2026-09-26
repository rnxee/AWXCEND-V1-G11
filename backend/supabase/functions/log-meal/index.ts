import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { dailyGoldKey } from '../_shared/gameDay.ts'

// One award per player per game day (Asia/Manila). The day is part of
// award_gold's idempotency key, so the limit is a unique index rather than a
// read-then-write check that two requests could both pass.
const DAILY_MEAL_GOLD = 10

const ALLOWED_METHODS = ['ai_scan', 'manual_scale', 'manual_entry']
const ALLOWED_MEAL_PERIODS = ['Breakfast', 'Lunch', 'Dinner', 'Snack']
const MAX_WEIGHT_G = 5000
const MAX_CALORIES = 10000
const MAX_MACRO_G = 2000
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const USDA_API_KEY = Deno.env.get('USDA_API_KEY') ?? ''
const USDA_TIMEOUT_MS = 6000

function isPositiveFinite(n: unknown, max: number): n is number {
  return typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= max
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

/**
 * Fetches a USDA record's per-100 g values from USDA itself, so a meal logged
 * "from USDA" is checked against USDA's numbers rather than whatever the client
 * sent. Returns null if it can't be verified (no key, USDA down, unknown id) —
 * the log is then labelled user_entered, never usda.
 */
async function fetchUsdaRecord(fdcId: number) {
  if (!USDA_API_KEY) return null
  try {
    const url = `https://api.nal.usda.gov/fdc/v1/food/${fdcId}?format=abridged&nutrients=208,957,958,203,204,205,291,269&api_key=${USDA_API_KEY}`
    const res = await fetch(url, { signal: AbortSignal.timeout(USDA_TIMEOUT_MS) })
    if (!res.ok) return null
    const food = await res.json()
    const list = Array.isArray(food?.foodNutrients) ? food.foodNutrients : []
    const num = (n: string) => {
      const hit = list.find((x: { number?: string }) => x.number === n)
      return typeof hit?.amount === 'number' ? hit.amount : null
    }
    // Energy is 208 on SR Legacy records; Foundation records may only carry the
    // Atwater variants (957 general, 958 specific).
    const calories = num('208') ?? num('958') ?? num('957')
    const protein = num('203')
    const fat = num('204')
    const carbs = num('205')
    if ([calories, protein, fat, carbs].some(v => v === null)) return null
    return {
      fdc_id: fdcId,
      description: String(food.description ?? ''),
      data_type: String(food.dataType ?? ''),
      per_100g: { calories, protein, carbs, fat, fiber: num('291'), sugar: num('269') }
    }
  } catch (err) {
    console.error('[log-meal] USDA verification failed:', (err as Error).message)
    return null
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  if (!(await checkRateLimit(user.id, 'log_meal', 60, 3600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const loggedMethod = typeof body.logged_method === 'string' ? body.logged_method.trim() : ''
  const foodName = typeof body.food_name === 'string' ? body.food_name.trim() : ''
  const mealPeriod = typeof body.meal_period === 'string' ? body.meal_period.trim() : ''
  // No feature uploads meal images, and storing an arbitrary client-supplied
  // URL let a log point anywhere. Refused here and by a table constraint.
  const imageUrlSent = typeof body.image_url === 'string' && body.image_url.trim() !== ''
  const weightG = Number(body.weight_g)
  const calories = Number(body.calories)
  const protein = Number(body.protein)
  const carbs = Number(body.carbs)
  const fat = Number(body.fat)
  const fiber = body.fiber === '' || body.fiber === undefined || body.fiber === null ? 0 : Number(body.fiber)
  const sugar = body.sugar === '' || body.sugar === undefined || body.sugar === null ? 0 : Number(body.sugar)
  // Which record the values came from — a reference only. The server decides
  // whether the values actually match it (see log_meal_entry).
  const foodId = typeof body.food_id === 'string' && body.food_id.trim() ? body.food_id.trim() : null
  const usdaFdcId = body.usda_fdc_id === undefined || body.usda_fdc_id === null || body.usda_fdc_id === '' ? null : Number(body.usda_fdc_id)
  const servingLabel = typeof body.serving_label === 'string' && body.serving_label.trim() ? body.serving_label.trim().slice(0, 60) : null

  const errors: string[] = []
  if (!ALLOWED_METHODS.includes(loggedMethod)) errors.push(`logged_method must be one of: ${ALLOWED_METHODS.join(', ')}`)
  if (!foodName) errors.push('food_name is required')
  if (foodName.length > 200) errors.push('food_name must be 200 characters or fewer')
  if (!ALLOWED_MEAL_PERIODS.includes(mealPeriod)) errors.push(`meal_period must be one of: ${ALLOWED_MEAL_PERIODS.join(', ')}`)
  if (!isPositiveFinite(weightG, MAX_WEIGHT_G)) errors.push(`weight_g must be between 0 and ${MAX_WEIGHT_G}`)
  if (!isPositiveFinite(calories, MAX_CALORIES)) errors.push(`calories must be between 0 and ${MAX_CALORIES}`)
  if (!isPositiveFinite(protein, MAX_MACRO_G)) errors.push(`protein must be between 0 and ${MAX_MACRO_G}`)
  if (!isPositiveFinite(carbs, MAX_MACRO_G)) errors.push(`carbs must be between 0 and ${MAX_MACRO_G}`)
  if (!isPositiveFinite(fat, MAX_MACRO_G)) errors.push(`fat must be between 0 and ${MAX_MACRO_G}`)
  if (!isPositiveFinite(fiber, MAX_MACRO_G)) errors.push(`fiber must be between 0 and ${MAX_MACRO_G}`)
  if (!isPositiveFinite(sugar, MAX_MACRO_G)) errors.push(`sugar must be between 0 and ${MAX_MACRO_G}`)
  if (foodId !== null && !UUID_RE.test(foodId)) errors.push('food_id must be a UUID')
  if (usdaFdcId !== null && !(Number.isInteger(usdaFdcId) && usdaFdcId > 0)) errors.push('usda_fdc_id must be a positive integer')
  if (foodId !== null && usdaFdcId !== null) errors.push('send food_id or usda_fdc_id, not both')
  if (imageUrlSent) errors.push('image_url is not accepted')

  if (errors.length > 0) return json({ success: false, errors }, 400)

  const usdaRecord = usdaFdcId !== null ? await fetchUsdaRecord(usdaFdcId) : null

  const admin = getAdminClient()
  const { data, error } = await admin.rpc('log_meal_entry', {
    p_user_id: user.id,
    p_logged_method: loggedMethod,
    p_food_name: foodName,
    p_weight_g: weightG,
    p_calories: calories,
    p_protein: protein,
    p_carbs: carbs,
    p_fat: fat,
    p_fiber: fiber,
    p_sugar: sugar,
    p_meal_period: mealPeriod,
    p_image_url: null,
    p_food_id: foodId,
    p_serving_label: servingLabel,
    p_usda: usdaRecord,
    p_usda_fdc_claimed: usdaFdcId
  })

  if (error) {
    const status = /UNKNOWN_FOOD|INVALID_SOURCE/.test(error.message) ? 400 : 500
    return json({ success: false, error: error.message }, status)
  }

  // Gold side-effect: first meal log of the day earns gold, every additional
  // log that day earns nothing. The unique index on gold_ledger.idempotency_key
  // makes that race-safe, and "today" is the game's day (Asia/Manila).
  const { data: goldResult, error: goldError } = await admin.rpc('award_gold', {
    p_user_id: user.id,
    p_amount: DAILY_MEAL_GOLD,
    p_reason: 'daily_meal_log',
    p_source_id: data.id,
    p_idempotency_key: dailyGoldKey('daily_meal_log', user.id)
  })

  // Non-fatal on purpose: the meal is already logged, so failing the whole
  // request over the gold bonus would lose the user's entry.
  if (goldError) console.error('[log-meal] gold award failed:', goldError.message)
  const goldAwarded = goldResult?.awarded ? DAILY_MEAL_GOLD : 0

  return json({ success: true, log: data, gold_awarded: goldAwarded })
})
