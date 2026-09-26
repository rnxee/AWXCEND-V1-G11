import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'

const USDA_API_KEY = Deno.env.get('USDA_API_KEY') ?? ''
const MAX_RESULTS = 8
// Search fires as the user types (debounced), so this allows brisk typing
// while still stopping a script from hammering USDA through our key.
const RL_MAX = 60
const RL_WINDOW_SECONDS = 60
const USDA_TIMEOUT_MS = 6000

// Standard USDA nutrient IDs — stable across the whole FoodData Central API.
const NUTRIENT_IDS = { calories: 1008, protein: 1003, fat: 1004, carbs: 1005, fiber: 1079, sugar: 2000 }

// Signals a result is a prepared/coated/processed variant rather than the
// plain whole food — e.g. "Chicken breast tenders, breaded" pulls in fiber
// from the breading, not the chicken. Ranked below plain matches so the
// first result is the one whose nutrients actually match what the name
// says, without hiding prepared foods entirely for someone who wants them.
const PREPARED_KEYWORDS = [
  'breaded', 'batter', 'fried', 'coated', 'glazed', 'seasoned', 'marinated',
  'smoked', 'deli', 'rotisserie', 'bbq', 'teriyaki', 'honey', 'nugget',
  'patty', 'sausage', 'loaf', 'roll', 'spread', 'fat-free', 'meal',
  'sauce', 'gravy', 'stuffed', 'processed', 'canned', 'soup', 'imitation'
]

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

// Every result has the same shape whichever source it came from, and the
// SERVER sets source / is_estimate / estimate_note — the client only displays
// them. Local foods come from public.search_foods(); USDA results are labelled
// as USDA data and never as Philippine foods.
type Result = {
  result_key: string
  food: {
    food_id: string | null
    usda_fdc_id: number | null
    name: string
    description: string | null
    local_names: string[]
    category: string
    region: string
    preparation: string | null
    nutrition: { basis: 'per_100g'; calories: number; protein: number; carbs: number; fat: number; fiber: number | null; sugar: number | null }
    source: string
    source_reference: string
    is_estimate: boolean
    estimate_note: string | null
  }
  servings: { label: string; grams: number; is_estimate: boolean }[]
}

async function searchUsda(query: string, limit: number): Promise<Result[]> {
  // Restricted to Foundation/SR Legacy — generic "chicken breast, raw" style
  // entries with clean per-100g values. Branded and survey (FNDDS) entries are
  // excluded for the same reasons as before: noisy product-specific macros and
  // pre-combined meals.
  const usdaUrl = new URL('https://api.nal.usda.gov/fdc/v1/foods/search')
  usdaUrl.searchParams.set('api_key', USDA_API_KEY)
  usdaUrl.searchParams.set('query', query)
  usdaUrl.searchParams.set('dataType', 'Foundation,SR Legacy')
  usdaUrl.searchParams.set('pageSize', String(limit * 2)) // over-fetch to survive the empty-nutrient filter

  const res = await fetch(usdaUrl.toString(), { signal: AbortSignal.timeout(USDA_TIMEOUT_MS) })
  if (!res.ok) throw new Error(`USDA responded ${res.status}`)
  const data = await res.json()
  const foods = Array.isArray(data?.foods) ? data.foods : []

  const queryLower = query.toLowerCase()
  const candidates: (Result & { isPrepared: boolean })[] = []
  for (const food of foods) {
    const nutrients = Array.isArray(food.foodNutrients) ? food.foodNutrients : []
    const get = (id: number) => nutrients.find((n: { nutrientId: number }) => n.nutrientId === id)?.value
    const calories = get(NUTRIENT_IDS.calories)
    const protein = get(NUTRIENT_IDS.protein)
    const fat = get(NUTRIENT_IDS.fat)
    const carbs = get(NUTRIENT_IDS.carbs)
    // Some entries come back with an empty nutrient list (a USDA search quirk);
    // they're dropped rather than shown with blank macros.
    if ([calories, protein, fat, carbs].some(v => typeof v !== 'number')) continue
    const fiber = get(NUTRIENT_IDS.fiber)
    const sugar = get(NUTRIENT_IDS.sugar)

    const descLower = String(food.description).toLowerCase()
    const isPrepared = PREPARED_KEYWORDS.some(kw => descLower.includes(kw) && !queryLower.includes(kw))

    candidates.push({
      result_key: `usda:${food.fdcId}`,
      food: {
        food_id: null,
        usda_fdc_id: food.fdcId,
        name: food.description,
        description: null,
        local_names: [],
        category: 'generic',
        region: 'international',
        preparation: null,
        nutrition: {
          basis: 'per_100g', calories, protein, carbs, fat,
          fiber: typeof fiber === 'number' ? fiber : null,
          sugar: typeof sugar === 'number' ? sugar : null
        },
        source: 'usda',
        source_reference: `USDA FoodData Central ${food.dataType}, FDC ${food.fdcId}`,
        is_estimate: false,
        estimate_note: null
      },
      servings: [],
      isPrepared
    })
  }
  candidates.sort((a, b) => Number(a.isPrepared) - Number(b.isPrepared))
  return candidates.slice(0, limit).map(({ isPrepared: _p, ...rest }) => rest)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  if (!(await checkRateLimit(user.id, 'search_food', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const url = new URL(req.url)
  const query = (url.searchParams.get('query') ?? '').trim().slice(0, 100)
  if (!query) return json({ success: false, errors: ['query is required'] }, 400)

  // 1. Local foods first — Philippine staples with Tagalog names.
  const admin = getAdminClient()
  const { data: local, error: localError } = await admin.rpc('search_foods', { p_query: query, p_limit: MAX_RESULTS })
  if (localError) console.error('[search-food] local search failed:', localError.message)
  const localResults: Result[] = (Array.isArray(local) ? local : []).map((r: { food: Result['food']; servings: Result['servings'] }) => ({
    result_key: `food:${r.food.food_id}`,
    food: { ...r.food, usda_fdc_id: null },
    servings: r.servings ?? []
  }))

  // 2. USDA fills any remaining slots. A USDA outage no longer fails the whole
  // search — local results still come back, and the client is told why USDA
  // results are missing.
  let usdaStatus: 'ok' | 'unavailable' | 'not_configured' | 'not_needed' = 'not_needed'
  let usdaResults: Result[] = []
  const remaining = MAX_RESULTS - localResults.length
  if (remaining > 0) {
    if (!USDA_API_KEY) {
      usdaStatus = 'not_configured'
    } else {
      try {
        usdaResults = await searchUsda(query, remaining)
        usdaStatus = 'ok'
      } catch (err) {
        console.error('[search-food] USDA search failed:', (err as Error).message)
        usdaStatus = 'unavailable'
      }
    }
  }

  if (localError && usdaStatus !== 'ok') {
    return json({ success: false, error: 'Food search is unavailable right now. You can still enter the nutrition yourself.' }, 502)
  }

  return json({ success: true, results: [...localResults, ...usdaResults], usda_status: usdaStatus })
})
