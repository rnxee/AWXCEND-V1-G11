// Daily macro targets, estimated from the user's profile.
//
// Shared by get-suggestions (coaching text) and budget-assistant (protein
// target shown next to food costs), so both screens show the same number.
// Moved here unchanged from get-suggestions; src/lib/macroTargets.test.js pins
// the outputs recorded before the move. Pure — no Deno APIs — so the tests can
// import it directly.

// Per-focus-type macro tuning. protein/kg and fat% drive the split; goalMultiplier
// is the calorie direction assumed when the user hasn't explicitly set a bulk/cut/
// maintain goal — e.g. "aesthetic" defaults to a slight cut, "powerlifter" a slight
// surplus, matching what each focus type is normally trying to achieve.
export const FOCUS_MACRO_PROFILES: Record<string, { proteinPerKg: number; fatPercent: number; goalMultiplier: number }> = {
  hybrid: { proteinPerKg: 1.6, fatPercent: 0.25, goalMultiplier: 1.0 },
  powerlifter: { proteinPerKg: 1.8, fatPercent: 0.20, goalMultiplier: 1.05 },
  cali: { proteinPerKg: 1.7, fatPercent: 0.25, goalMultiplier: 1.0 },
  aesthetic: { proteinPerKg: 2.0, fatPercent: 0.25, goalMultiplier: 0.9 }
}

export const GOAL_MULTIPLIERS: Record<string, number> = { bulk: 1.10, cut: 0.80, maintain: 1.0 }

export type MacroTarget = { calories: number; protein: number; carbs: number; fat: number; fiber: number; sugar: number }

export type MacroProfileInput = {
  weight_kg: number | null
  height_cm: number | null
  sex: string | null
  age: number | null
  goal: string | null
  focus_type: string | null
}

/** Null when weight or height is missing — no target can be estimated. */
export function computeMacroTarget(profile: MacroProfileInput): MacroTarget | null {
  const { weight_kg: weightKg, height_cm: heightCm, sex, age, goal, focus_type: focusType } = profile
  const macroProfile = FOCUS_MACRO_PROFILES[focusType ?? ''] ?? FOCUS_MACRO_PROFILES.hybrid

  // Macro math is done here, deterministically — not left to the LLM, which
  // is unreliable at arithmetic (especially a small local model). The LLM
  // only ever writes coaching text around numbers we've already computed.
  if (!(weightKg && heightCm)) return null

  // Mifflin-St Jeor BMR. Sex/age are optional too — fall back to the
  // midpoint of the male/female constant when either is missing, which
  // keeps the estimate roughly in range without forcing the user to fill
  // in fields they skipped.
  const sexOffset = sex === 'male' ? 5 : sex === 'female' ? -161 : -78
  const ageTerm = age ? 5 * age : 5 * 30
  const bmr = 10 * weightKg + 6.25 * heightCm - ageTerm + sexOffset

  // No activity-level input exists yet, so this assumes "moderately
  // active" (exercise 3-5x/week) — reasonable default for a gym app,
  // but worth surfacing as an assumption rather than false precision.
  // Calorie direction (bulk/cut/maintain) comes from the user's explicit
  // goal when set, otherwise from what their focus type usually implies.
  const goalMultiplier = goal ? GOAL_MULTIPLIERS[goal] : macroProfile.goalMultiplier
  const tdee = bmr * 1.55 * goalMultiplier

  const proteinG = weightKg * macroProfile.proteinPerKg
  const fatG = (tdee * macroProfile.fatPercent) / 9
  const proteinCals = proteinG * 4
  const fatCals = fatG * 9
  const carbsG = Math.max(0, (tdee - proteinCals - fatCals) / 4)

  // IOM guideline (14g fiber per 1000 kcal) — the actual lever behind
  // "fiber supports fat loss": it's satiety per calorie, not a macro that
  // itself burns fat, so it's tied to calorie target rather than weight.
  const fiberG = (tdee / 1000) * 14

  // WHO guideline (free sugars < 10% of total energy intake) — a ceiling,
  // not a target to hit. Tied to calories rather than weight for the same
  // reason as fiber: it's a proportion of intake, not a per-kg macro.
  const sugarG = (tdee * 0.10) / 4

  return {
    calories: Math.round(tdee),
    protein: Math.round(proteinG),
    carbs: Math.round(carbsG),
    fat: Math.round(fatG),
    fiber: Math.round(fiberG),
    sugar: Math.round(sugarG)
  }
}
