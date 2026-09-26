// Budget-assistant calculations. Pure — no Deno APIs — so the tests import it
// directly (src/lib/budgetMath.test.js).
//
// Every result keeps its three inputs apart, and says where each came from:
//   nutrition  — a public.foods record (USDA-derived estimate), per 100 g edible
//   price      — the user's own price, else the latest reference price: DA Bantay
//                Presyo NCR, or an admin adjustment (with a note on where it was seen)
//   waste      — the inedible share, only when a source for it exists
// A cost per gram of protein is CALCULATED from those; it is labelled as a
// calculation, never as Philippine price or nutrition data in its own right.

/** Classification rule for the protein-swap comparison — not a recommendation. */
export const PROTEIN_SWAP_MIN_KCAL_SHARE = 0.20
/** DA reference prices older than this (after the period ends) are flagged. */
export const PRICE_OUTDATED_AFTER_DAYS = 30
/** Comparisons are expressed per this many grams of protein. */
export const PROTEIN_COMPARISON_GRAMS = 25

export const MAX_ESTIMATE_ITEMS = 20
export const MAX_ESTIMATE_PIECES = 100
export const MAX_ESTIMATE_GRAMS = 10000
export const MAX_PRICE_PHP = 100000
export const MAX_DAILY_BUDGET_PHP = 100000

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/

export type FoodRow = {
  food_id: string
  slug: string
  name: string
  calories: number
  protein: number
  carbs: number
  fat: number
  source: string
  source_reference: string
  is_estimate: boolean
  estimate_note: string | null
}

export type ReferencePriceRow = {
  id: string
  price_php: number
  unit: string
  region: string
  period_start: string
  period_end: string
  source: string
  source_label: string
  source_reference: string | null
  source_item: string
  specification: string | null
  note?: string | null
}

export type UserPriceRow = { id: string; price_php: number | null; unit: string; entered_at: string }

export type CommodityRow = {
  slug: string
  name: string
  local_names: string[]
  commodity_group: string
  purchase_unit: 'kg' | 'piece'
  grams_per_piece: number | null
  grams_per_piece_source: string | null
  inedible_share: number | null
  inedible_share_source: string | null
  calculation_note: string
  food: FoodRow | null
  reference_price: ReferencePriceRow | null
  user_price: UserPriceRow | null
}

export type CalculationStatus = 'calculated' | 'needs_price' | 'price_only' | 'unavailable'

const round2 = (n: number) => Math.round(n * 100) / 100
const round1 = (n: number) => Math.round(n * 10) / 10
const round3 = (n: number) => Math.round(n * 1000) / 1000

/** Whole days from one 'YYYY-MM-DD' date to another (negative if earlier). */
export function daysBetween(fromDate: string, toDate: string): number {
  const a = Date.parse(`${fromDate.slice(0, 10)}T00:00:00Z`)
  const b = Date.parse(`${toDate.slice(0, 10)}T00:00:00Z`)
  return Math.round((b - a) / 86400000)
}

/**
 * Which price applies, and what it is. The user's latest non-cleared price
 * wins; otherwise the latest DA reference price. The reference is always
 * returned alongside, so a screen can show both.
 */
export function resolvePrice(c: CommodityRow, today: string) {
  const ref = c.reference_price
  const reference = ref
    ? {
        price_php: Number(ref.price_php),
        unit: ref.unit,
        region: ref.region,
        period: { start: ref.period_start, end: ref.period_end },
        source: ref.source,
        source_label: ref.source_label,
        source_reference: ref.source_reference,
        source_item: ref.source_item,
        specification: ref.specification,
        note: ref.note ?? null,
        age_days: daysBetween(ref.period_end, today),
        outdated: daysBetween(ref.period_end, today) > PRICE_OUTDATED_AFTER_DAYS
      }
    : null

  const user = c.user_price && c.user_price.price_php !== null
    ? { price_php: Number(c.user_price.price_php), entered_at: c.user_price.entered_at }
    : null

  if (user) {
    return {
      price_php: user.price_php,
      price_unit: c.purchase_unit,
      price_source: 'user_entered' as const,
      price_is_user_override: true,
      price_period: null,
      price_entered_at: user.entered_at,
      price_outdated: false,
      reference_price: reference
    }
  }
  if (reference) {
    return {
      price_php: reference.price_php,
      price_unit: c.purchase_unit,
      price_source: reference.source as 'da_bantay_presyo' | 'admin_adjustment',
      price_is_user_override: false,
      price_period: reference.period,
      price_entered_at: null,
      price_outdated: reference.outdated,
      reference_price: reference
    }
  }
  return {
    price_php: null,
    price_unit: c.purchase_unit,
    price_source: null,
    price_is_user_override: false,
    price_period: null,
    price_entered_at: null,
    price_outdated: false,
    reference_price: null
  }
}

/** Nutrition can be calculated from a bought amount only with a sourced waste share. */
export function nutritionCalculable(c: CommodityRow): boolean {
  return c.food !== null && c.inedible_share !== null && c.inedible_share !== undefined
}

export function calculationStatus(c: CommodityRow, hasPrice: boolean): CalculationStatus {
  const calculable = nutritionCalculable(c)
  if (calculable && hasPrice) return 'calculated'
  if (calculable) return 'needs_price'
  if (hasPrice) return 'price_only'
  return 'unavailable'
}

/** Share of the food's calories that come from protein (4 kcal/g), or null. */
export function proteinKcalShare(food: FoodRow | null): number | null {
  if (!food || !(Number(food.calories) > 0)) return null
  return round3((4 * Number(food.protein)) / Number(food.calories))
}

/** Bought grams in one purchase unit (1 kg, or one piece as sold). */
export function gramsPerPurchaseUnit(c: CommodityRow): number | null {
  if (c.purchase_unit === 'kg') return 1000
  return c.grams_per_piece === null ? null : Number(c.grams_per_piece)
}

/**
 * Cost and nutrition side-effects of 25 g of protein from this commodity.
 * `php` needs a price; the nutrition differences don't.
 */
export function perProteinComparison(c: CommodityRow, pricePhp: number | null) {
  if (!nutritionCalculable(c)) return null
  const food = c.food as FoodRow
  const protein = Number(food.protein)
  if (!(protein > 0)) return null
  const factor = PROTEIN_COMPARISON_GRAMS / protein // edible grams per 25 g protein ÷ 100
  let php: number | null = null
  const unitGrams = gramsPerPurchaseUnit(c)
  if (pricePhp !== null && unitGrams) {
    const proteinPerUnit = unitGrams * (1 - Number(c.inedible_share)) * protein / 100
    php = proteinPerUnit > 0 ? round2((pricePhp / proteinPerUnit) * PROTEIN_COMPARISON_GRAMS) : null
  }
  return {
    protein_g: PROTEIN_COMPARISON_GRAMS,
    php,
    kcal: round1(factor * Number(food.calories)),
    fat_g: round1(factor * Number(food.fat)),
    carbs_g: round1(factor * Number(food.carbs))
  }
}

function nutritionFields(c: CommodityRow) {
  const f = c.food
  return {
    nutrition_source: f ? f.source : null,
    nutrition_is_estimate: f ? f.is_estimate : null,
    nutrition_estimate_note: f ? f.estimate_note : null,
    nutrition_reference: f ? f.source_reference : null,
    nutrition_food: f ? { food_id: f.food_id, slug: f.slug, name: f.name } : null,
    nutrition_per_100g_edible: f
      ? { calories: Number(f.calories), protein: Number(f.protein), carbs: Number(f.carbs), fat: Number(f.fat) }
      : null
  }
}

/** One commodity as budget-assistant returns it. */
export function describeCommodity(c: CommodityRow, today: string) {
  const price = resolvePrice(c, today)
  const status = calculationStatus(c, price.price_php !== null)
  const share = nutritionCalculable(c) ? proteinKcalShare(c.food) : null
  return {
    slug: c.slug,
    name: c.name,
    local_names: c.local_names ?? [],
    commodity_group: c.commodity_group,
    purchase_unit: c.purchase_unit,
    grams_per_piece: c.grams_per_piece === null ? null : Number(c.grams_per_piece),
    grams_per_piece_source: c.grams_per_piece_source,
    ...nutritionFields(c),
    ...price,
    inedible_share: c.inedible_share === null ? null : Number(c.inedible_share),
    inedible_share_source: c.inedible_share_source,
    calculation_status: status,
    calculation_note: c.calculation_note,
    protein_kcal_share: share,
    // Classification only: whether the food is included in the protein-swap
    // comparison. It says nothing about whether anyone should eat it.
    protein_swap_eligible: share !== null && share >= PROTEIN_SWAP_MIN_KCAL_SHARE,
    per_25g_protein: perProteinComparison(c, price.price_php),
    cheaper_protein_alternatives: [] as Array<{
      slug: string; name: string; php_per_25g_protein: number
      php_difference: number; kcal_difference: number; fat_g_difference: number
    }>
  }
}

export type CommodityView = ReturnType<typeof describeCommodity>

/**
 * All commodities, with each eligible one's cheaper alternatives in the same
 * group (ordered cheapest first, with the differences that come with them).
 */
export function buildOverview(rows: CommodityRow[], today: string) {
  const items = rows.map(r => describeCommodity(r, today))
  for (const item of items) {
    const php = item.per_25g_protein?.php
    if (!item.protein_swap_eligible || php === null || php === undefined) continue
    item.cheaper_protein_alternatives = items
      .filter(o => o !== item && o.protein_swap_eligible && o.commodity_group === item.commodity_group &&
        o.per_25g_protein?.php !== null && o.per_25g_protein?.php !== undefined && (o.per_25g_protein.php as number) < php)
      .sort((a, b) => (a.per_25g_protein!.php as number) - (b.per_25g_protein!.php as number))
      .map(o => ({
        slug: o.slug,
        name: o.name,
        php_per_25g_protein: o.per_25g_protein!.php as number,
        php_difference: round2((o.per_25g_protein!.php as number) - php),
        kcal_difference: round1(o.per_25g_protein!.kcal - item.per_25g_protein!.kcal),
        fat_g_difference: round1(o.per_25g_protein!.fat_g - item.per_25g_protein!.fat_g)
      }))
  }
  return items
}

export type EstimateItemInput = { commodity: string; amount: number }

/** Validates an estimate request. Units come from the commodity, not the client. */
export function parseEstimateItems(raw: unknown, commodities: Map<string, CommodityRow>) {
  const errors: string[] = []
  if (!Array.isArray(raw) || raw.length === 0) return { items: [], errors: ['items must be a non-empty list'] }
  if (raw.length > MAX_ESTIMATE_ITEMS) return { items: [], errors: [`at most ${MAX_ESTIMATE_ITEMS} items`] }
  const items: EstimateItemInput[] = []
  raw.forEach((entry, i) => {
    const slug = typeof entry?.commodity === 'string' ? entry.commodity : ''
    const amount = Number(entry?.amount)
    const c = SLUG_RE.test(slug) ? commodities.get(slug) : undefined
    if (!c) { errors.push(`item ${i + 1}: unknown item`); return }
    if (c.purchase_unit === 'piece') {
      if (!Number.isInteger(amount) || amount < 1 || amount > MAX_ESTIMATE_PIECES) {
        errors.push(`item ${i + 1}: ${c.name} is counted in whole pieces (1-${MAX_ESTIMATE_PIECES})`)
        return
      }
    } else if (!Number.isFinite(amount) || amount <= 0 || amount > MAX_ESTIMATE_GRAMS) {
      errors.push(`item ${i + 1}: ${c.name} needs an amount in grams, more than 0 and at most ${MAX_ESTIMATE_GRAMS}`)
      return
    }
    items.push({ commodity: slug, amount })
  })
  return { items, errors }
}

/** Cost and nutrition of raw bought amounts. Cooked yield is never inferred. */
export function estimateMeal(
  inputs: EstimateItemInput[],
  commodities: Map<string, CommodityRow>,
  today: string,
  context: { dailyBudgetPhp: number | null; proteinTargetG: number | null }
) {
  const items = inputs.map(input => {
    const c = commodities.get(input.commodity) as CommodityRow
    const price = resolvePrice(c, today)
    const status = calculationStatus(c, price.price_php !== null)
    const unitGrams = gramsPerPurchaseUnit(c)
    const boughtGrams = c.purchase_unit === 'piece'
      ? (unitGrams === null ? null : round1(input.amount * unitGrams))
      : round1(input.amount)
    const units = c.purchase_unit === 'piece' ? input.amount : input.amount / 1000
    const cost = price.price_php === null ? null : round2(price.price_php * units)

    let edibleGrams: number | null = null
    let nutrition: { calories: number; protein: number; carbs: number; fat: number } | null = null
    if (nutritionCalculable(c) && boughtGrams !== null) {
      const food = c.food as FoodRow
      const edible = (c.purchase_unit === 'piece' ? input.amount * (unitGrams as number) : input.amount) *
        (1 - Number(c.inedible_share))
      edibleGrams = round1(edible)
      const k = edible / 100
      nutrition = {
        calories: round1(Number(food.calories) * k),
        protein: round1(Number(food.protein) * k),
        carbs: round1(Number(food.carbs) * k),
        fat: round1(Number(food.fat) * k)
      }
    }

    return {
      commodity: c.slug,
      name: c.name,
      amount: input.amount,
      amount_unit: c.purchase_unit === 'piece' ? 'piece' : 'g',
      bought_grams: boughtGrams,
      cost_php: cost,
      ...price,
      calculation_status: status,
      calculation_note: c.calculation_note,
      inedible_share: c.inedible_share === null ? null : Number(c.inedible_share),
      inedible_share_source: c.inedible_share_source,
      edible_grams: edibleGrams,
      nutrition,
      ...nutritionFields(c)
    }
  })

  const priced = items.filter(i => i.cost_php !== null)
  const withNutrition = items.filter(i => i.nutrition !== null)
  const costTotal = round2(priced.reduce((s, i) => s + (i.cost_php as number), 0))
  const nutritionTotal = withNutrition.length === 0 ? null : {
    calories: round1(withNutrition.reduce((s, i) => s + i.nutrition!.calories, 0)),
    protein: round1(withNutrition.reduce((s, i) => s + i.nutrition!.protein, 0)),
    carbs: round1(withNutrition.reduce((s, i) => s + i.nutrition!.carbs, 0)),
    fat: round1(withNutrition.reduce((s, i) => s + i.nutrition!.fat, 0))
  }

  return {
    items,
    totals: {
      cost_php: priced.length === 0 ? null : costTotal,
      // Incomplete totals are still returned, but flagged, and the items
      // missing from them are named.
      cost_complete: priced.length === items.length,
      items_without_price: items.filter(i => i.cost_php === null).map(i => i.commodity),
      nutrition: nutritionTotal,
      nutrition_complete: withNutrition.length === items.length,
      items_without_nutrition: items.filter(i => i.nutrition === null).map(i => i.commodity),
      any_price_outdated: items.some(i => i.price_outdated),
      any_user_price: items.some(i => i.price_is_user_override)
    },
    share_of_daily_budget: context.dailyBudgetPhp && priced.length > 0
      ? round3(costTotal / context.dailyBudgetPhp) : null,
    share_of_protein_target: context.proteinTargetG && nutritionTotal
      ? round3(nutritionTotal.protein / context.proteinTargetG) : null
  }
}

/** A price or budget from a request: a number in range, or null to clear. */
export const MIN_PRICE_NOTE = 3
export const MAX_PRICE_NOTE = 200

/** An admin price adjustment must say where the price was seen. */
export function parsePriceNote(raw: unknown): { value: string | null; error: string | null } {
  if (typeof raw !== 'string') return { value: null, error: 'Say where this price was seen' }
  const v = raw.trim()
  if (v.length < MIN_PRICE_NOTE || v.length > MAX_PRICE_NOTE) {
    return { value: null, error: `Note must be ${MIN_PRICE_NOTE}–${MAX_PRICE_NOTE} characters` }
  }
  return { value: v, error: null }
}

export function parseMoney(raw: unknown, max: number): { value: number | null; error: string | null } {
  if (raw === null) return { value: null, error: null }
  const n = typeof raw === 'number' ? raw : typeof raw === 'string' && raw.trim() !== '' ? Number(raw) : NaN
  if (!Number.isFinite(n) || n <= 0 || n > max) {
    return { value: null, error: `must be more than ₱0 and at most ₱${max.toLocaleString('en-PH')}` }
  }
  return { value: Math.round(n * 100) / 100, error: null }
}
