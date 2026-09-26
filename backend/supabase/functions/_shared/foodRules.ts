// Rules for foods that admins add or edit by hand (Admin Panel → Foods).
// Pure, so src/lib/foodRules.test.js can import and test them directly.
//
// The food database used to be maintained by migration only. Admins can now
// maintain it themselves, and the rules below keep it as honest as the seeded
// rows are:
//
//  - every food says where its numbers come from (source + reference);
//  - an estimate says why it is one;
//  - PhilFCT cannot be chosen — its reuse needs written FNRI permission that
//    the project does not have yet;
//  - values have to be physically possible for 100 g of food.
//
// Two rules live only in the database (admin_save_food), because they need
// the stored row: changing nutrition values requires a new source or
// reference, and an edit based on an out-of-date copy is refused. The
// database also re-checks the source list and the physical limits, so it
// stays the authority if this file and the migration ever disagree.
//
// Past meal logs are never affected by an edit: each log keeps a snapshot of
// the values it was logged with.

export const ADMIN_FOOD_SOURCES = ['label', 'manual_estimate', 'usda', 'usda_derived'] as const
export const FOOD_CATEGORIES = ['generic', 'branded', 'ingredient', 'prepared_meal'] as const
export const FOOD_REGIONS = ['ph', 'asia', 'international'] as const
export const FOOD_PREPARATIONS = [
  'raw', 'boiled', 'fried', 'grilled', 'steamed', 'stewed', 'baked', 'dried', 'canned', 'cooked'
] as const

// A manual estimate or a USDA-derived value is an estimate by definition.
export const ESTIMATE_ONLY_SOURCES = ['manual_estimate', 'usda_derived'] as const

export const NUTRIENTS = ['calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar'] as const
export const REQUIRED_NUTRIENTS = ['calories', 'protein', 'carbs', 'fat'] as const

export const LIMITS = {
  name: 120,
  description: 500,
  brand: 80,
  sourceReference: 300,
  estimateNote: 500,
  namesPerList: 10,
  nameLength: 60,
  servings: 8,
  servingLabel: 60,
  servingGrams: 2000,
  calories: 900,
  macro: 100
} as const

// Protein, carbs and fat can't add up to more than 100 g in 100 g of food. The
// extra gram allows for labels that round each value up.
export const MACRO_SUM_TOLERANCE = 1

// Energy is checked against the usual 4/4/9 kcal per gram. A mismatch is often
// a typo (52 typed for 520), but it can be real (sugar alcohols, fibre, alcohol,
// label rounding), so it is a warning the admin has to confirm, not a refusal.
export const ENERGY_TOLERANCE_KCAL = 20
export const ENERGY_TOLERANCE_SHARE = 0.25

export type Serving = { label: string; grams: number }

export type FoodInput = {
  name: string
  description: string | null
  local_names: string[]
  aliases: string[]
  category: string
  region: string
  preparation: string | null
  brand: string | null
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number | null
  sugar: number | null
  source: string
  source_reference: string
  is_estimate: boolean
  estimate_note: string | null
  servings: Serving[]
}

const round1 = (n: number) => Math.round(n * 10) / 10

function text(raw: unknown): string {
  return typeof raw === 'string' ? raw.trim().replace(/\s+/g, ' ') : ''
}

function optionalText(raw: unknown): string | null {
  const t = text(raw)
  return t ? t : null
}

// '' and null mean "not given"; anything else must be a finite number.
function number(raw: unknown): number | null | 'invalid' {
  if (raw === null || raw === undefined || raw === '') return null
  const n = typeof raw === 'number' ? raw : Number(String(raw).trim())
  return Number.isFinite(n) ? round1(n) : 'invalid'
}

function nameList(raw: unknown, label: string, errors: string[]): string[] {
  const items = Array.isArray(raw) ? raw : typeof raw === 'string' ? raw.split(',') : []
  const out: string[] = []
  const seen = new Set<string>()
  for (const item of items) {
    const t = text(item)
    if (!t) continue
    if (t.length > LIMITS.nameLength) {
      errors.push(`${label}: "${t.slice(0, 20)}…" is longer than ${LIMITS.nameLength} characters.`)
      continue
    }
    const key = t.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    out.push(t)
  }
  if (out.length > LIMITS.namesPerList) errors.push(`${label}: at most ${LIMITS.namesPerList} names.`)
  return out
}

/** A URL-safe id made from the name: "Chicken Adobo (Ñ)" → "chicken-adobo-n". */
export function slugify(name: string): string {
  const slug = name
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60)
    .replace(/-+$/g, '')
  return slug || 'food'
}

/** kcal from macros, and whether the stated calories are far from it. */
export function energyCheck(food: { calories: number; protein: number; carbs: number; fat: number }) {
  const expected = Math.round(4 * food.protein + 4 * food.carbs + 9 * food.fat)
  const allowed = Math.max(ENERGY_TOLERANCE_KCAL, expected * ENERGY_TOLERANCE_SHARE)
  return { expected, mismatch: Math.abs(food.calories - expected) > allowed }
}

/**
 * Cleans and validates what the admin submitted. Returns the normalised food
 * or the list of problems — never a half-valid food.
 */
export function normalizeFoodInput(raw: Record<string, unknown>, opts: { energyConfirmed?: boolean } = {}):
  { ok: true; food: FoodInput; energy: { expected: number; mismatch: boolean } }
  | { ok: false; errors: string[]; energyExpected?: number } {
  const errors: string[] = []

  const name = text(raw.name)
  if (!name) errors.push('Name is required.')
  else if (name.length > LIMITS.name) errors.push(`Name must be ${LIMITS.name} characters or fewer.`)

  const description = optionalText(raw.description)
  if (description && description.length > LIMITS.description) {
    errors.push(`Description must be ${LIMITS.description} characters or fewer.`)
  }

  const local_names = nameList(raw.local_names, 'Local names', errors)
  const aliases = nameList(raw.aliases, 'Other names', errors)

  const category = text(raw.category)
  if (!(FOOD_CATEGORIES as readonly string[]).includes(category)) errors.push('Pick a category.')
  const region = text(raw.region)
  if (!(FOOD_REGIONS as readonly string[]).includes(region)) errors.push('Pick a region.')
  const preparation = optionalText(raw.preparation)
  if (preparation && !(FOOD_PREPARATIONS as readonly string[]).includes(preparation)) errors.push('Pick a valid preparation.')

  const brand = optionalText(raw.brand)
  if (brand && brand.length > LIMITS.brand) errors.push(`Brand must be ${LIMITS.brand} characters or fewer.`)
  if (category === 'branded' && !brand) errors.push('A branded food needs its brand.')

  const values: Record<string, number | null> = {}
  for (const key of NUTRIENTS) {
    const v = number(raw[key])
    const label = key.charAt(0).toUpperCase() + key.slice(1)
    if (v === 'invalid') { errors.push(`${label} must be a number.`); continue }
    if (v === null) {
      if ((REQUIRED_NUTRIENTS as readonly string[]).includes(key)) errors.push(`${label} per 100 g is required.`)
      values[key] = null
      continue
    }
    const max = key === 'calories' ? LIMITS.calories : LIMITS.macro
    if (v < 0 || v > max) errors.push(`${label} per 100 g must be between 0 and ${max}.`)
    values[key] = v
  }

  const { protein, carbs, fat, sugar } = values
  if (typeof protein === 'number' && typeof carbs === 'number' && typeof fat === 'number' &&
      protein + carbs + fat > LIMITS.macro + MACRO_SUM_TOLERANCE) {
    errors.push(`Protein, carbs and fat add up to ${round1(protein + carbs + fat)} g — more than 100 g of food can hold.`)
  }
  if (typeof sugar === 'number' && typeof carbs === 'number' && sugar > carbs + 0.5) {
    errors.push('Sugar is part of carbohydrates, so it can’t be higher than carbs.')
  }

  const source = text(raw.source)
  if (source === 'philfct') {
    errors.push('PhilFCT can’t be used yet: its data needs written permission from DOST-FNRI.')
  } else if (!(ADMIN_FOOD_SOURCES as readonly string[]).includes(source)) {
    errors.push('Say where the numbers come from.')
  }

  const source_reference = text(raw.source_reference)
  if (!source_reference) errors.push('Add a source reference, e.g. the product and label date, or the USDA FDC number.')
  else if (source_reference.length > LIMITS.sourceReference) {
    errors.push(`Source reference must be ${LIMITS.sourceReference} characters or fewer.`)
  }

  const is_estimate = raw.is_estimate === true
  if ((ESTIMATE_ONLY_SOURCES as readonly string[]).includes(source) && !is_estimate) {
    errors.push('That source is an estimate by definition — mark it as one and say why.')
  }
  const estimate_note = is_estimate ? optionalText(raw.estimate_note) : null
  if (is_estimate && !estimate_note) errors.push('Explain why these values are an estimate.')
  if (estimate_note && estimate_note.length > LIMITS.estimateNote) {
    errors.push(`Estimate note must be ${LIMITS.estimateNote} characters or fewer.`)
  }

  const servings: Serving[] = []
  const servingRaw = Array.isArray(raw.servings) ? raw.servings : []
  const seenLabels = new Set<string>()
  for (const s of servingRaw as Record<string, unknown>[]) {
    const label = text(s?.label)
    const grams = number(s?.grams)
    if (!label && (grams === null)) continue // an empty row the admin never filled
    if (!label) { errors.push('Every serving needs a label, e.g. "1 cup".'); continue }
    if (label.length > LIMITS.servingLabel) { errors.push(`Serving "${label.slice(0, 20)}…" has too long a label.`); continue }
    if (grams === 'invalid' || grams === null || grams <= 0 || grams > LIMITS.servingGrams) {
      errors.push(`Serving "${label}" needs a weight between 0 and ${LIMITS.servingGrams} g.`)
      continue
    }
    const key = label.toLowerCase()
    if (seenLabels.has(key)) { errors.push(`Serving "${label}" is listed twice.`); continue }
    seenLabels.add(key)
    servings.push({ label, grams })
  }
  if (servings.length > LIMITS.servings) errors.push(`At most ${LIMITS.servings} servings.`)

  if (errors.length > 0) return { ok: false, errors }

  const food: FoodInput = {
    name, description, local_names, aliases, category, region, preparation, brand,
    calories: values.calories as number,
    protein: values.protein as number,
    carbs: values.carbs as number,
    fat: values.fat as number,
    fiber: values.fiber,
    sugar: values.sugar,
    source, source_reference, is_estimate, estimate_note, servings
  }

  const energy = energyCheck(food)
  if (energy.mismatch && !opts.energyConfirmed) {
    return {
      ok: false,
      energyExpected: energy.expected,
      errors: [`Calories (${food.calories}) are far from what the macros give (about ${energy.expected} kcal). Check for a typo, or confirm the values are right.`]
    }
  }
  return { ok: true, food, energy }
}

const asNum = (v: unknown) => (v === null || v === undefined || v === '' ? null : round1(Number(v)))

/** Field names that differ, for the audit log. Servings compare as a whole. */
export function changedFields(before: Record<string, unknown>, after: FoodInput): string[] {
  const fields: string[] = []
  const simple = [
    'name', 'description', 'category', 'region', 'preparation', 'brand',
    'source', 'source_reference', 'is_estimate', 'estimate_note'
  ] as const
  for (const f of simple) {
    if ((before[f] ?? null) !== (after[f] ?? null)) fields.push(f)
  }
  for (const f of NUTRIENTS) if (asNum(before[f]) !== asNum(after[f])) fields.push(f)
  const list = (v: unknown) => JSON.stringify(Array.isArray(v) ? v : [])
  if (list(before.local_names) !== list(after.local_names)) fields.push('local_names')
  if (list(before.aliases) !== list(after.aliases)) fields.push('aliases')
  const servings = (v: unknown) => JSON.stringify(
    (Array.isArray(v) ? v : []).map((s: { label?: string; grams?: number | string }) => [s.label, asNum(s.grams)])
  )
  if (servings(before.servings) !== servings(after.servings)) fields.push('servings')
  return fields
}
