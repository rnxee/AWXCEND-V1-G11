// Strength tier thresholds, for the server side of the strength leaderboard.
//
// Mirrors STRENGTH_STANDARDS / resolveStrengthRank in src/lib/strengthScore.js.
// Two copies exist for the same reason as the specialization list: the
// frontend is plain JS and the edge functions are Deno TypeScript with no
// shared build step. src/lib/strengthScore.test.js reads this file and fails
// if the two ever disagree.
//
// The frontend computes the CURRENT user's tiers locally (no round trip); the
// server computes them for everyone on a leaderboard. Same arithmetic, two
// call sites.

export const STRENGTH_TIERS = [
  'Novice', 'Fighter', 'Warrior', 'Elite',
  'Master', 'Mythic', 'Titan', 'Monarch'
] as const

export const STRENGTH_SUB_RANKS = [5, 5, 5, 5, 5, 5, 5, 10]

// Bodyweight multiples per tier. Keyed on RELATIVE strength because an
// absolute threshold would make tiers a proxy for bodyweight. Ratios differ
// per lift by necessity: a 2x bodyweight deadlift is ordinary, a 2x
// bodyweight bench press is exceptional.
//
// KNOWN LIMITATION: male-referenced, unadjusted for age or sex. A rough guide,
// not a fair cross-population comparison — proper normalisation needs a
// coefficient table and is deliberately deferred.
export const STRENGTH_STANDARDS: Record<string, number[]> = {
  squat:             [0.50, 0.75, 1.00, 1.25, 1.50, 1.75, 2.00, 2.50],
  deadlift:          [0.60, 1.00, 1.25, 1.50, 1.75, 2.00, 2.50, 3.00],
  romaniandeadlift:  [0.50, 0.85, 1.10, 1.35, 1.60, 1.85, 2.20, 2.60],
  benchpress:        [0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75, 2.00],
  inclinebenchpress: [0.30, 0.45, 0.65, 0.85, 1.05, 1.30, 1.50, 1.75],
  declinebenchpress: [0.35, 0.55, 0.80, 1.05, 1.30, 1.55, 1.80, 2.10],
  shoulderpress:     [0.25, 0.40, 0.55, 0.70, 0.85, 1.00, 1.15, 1.35],
  hipthrust:         [0.75, 1.25, 1.75, 2.25, 2.75, 3.25, 3.75, 4.50],
  tbarrow:           [0.40, 0.60, 0.80, 1.00, 1.20, 1.40, 1.60, 1.90],
  latpulldown:       [0.40, 0.60, 0.80, 1.00, 1.20, 1.40, 1.60, 1.85],
  barbellbicepscurl: [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.90],
  hammercurl:        [0.15, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.85],

  // Olympic lifts. Far lower ratios than the powerlifts at the same tier:
  // what a lifter can snatch is a fraction of what they can deadlift, so
  // borrowing the deadlift ladder would park every Olympic lifter at Novice.
  snatch:            [0.30, 0.45, 0.60, 0.75, 0.95, 1.15, 1.35, 1.60],
  cleanandjerk:      [0.40, 0.55, 0.75, 0.95, 1.15, 1.40, 1.65, 1.95],
  powerclean:        [0.35, 0.50, 0.70, 0.90, 1.10, 1.30, 1.50, 1.75],

  // Strongman implements. Ratios are on TOTAL load carried, not per hand.
  farmerscarry:      [0.50, 0.80, 1.10, 1.40, 1.70, 2.00, 2.40, 2.90],
  atlasstone:        [0.40, 0.65, 0.90, 1.15, 1.40, 1.70, 2.00, 2.40],
  yokewalk:          [0.75, 1.10, 1.50, 1.90, 2.30, 2.70, 3.10, 3.60]
}

export const RANKABLE_LIFTS = Object.keys(STRENGTH_STANDARDS)

export function isRankableLift(exercise: string): boolean {
  return Object.prototype.hasOwnProperty.call(STRENGTH_STANDARDS, exercise)
}

export interface StrengthRank {
  tierName: string
  tier: number
  subRank: number
  subRanks: number
  displayRank: string
  isMaxed: boolean
}

export function resolveStrengthRank(
  exercise: string,
  relativeE1rm: number | null | undefined
): StrengthRank | null {
  const standards = STRENGTH_STANDARDS[exercise]
  if (!standards) return null

  const ratio = Number(relativeE1rm)
  if (!Number.isFinite(ratio) || ratio <= 0) return null

  let index = 0
  for (let i = 0; i < standards.length; i++) {
    if (standards[i] <= ratio) index = i
  }

  const tierFloor = standards[index]
  const nextFloor = index + 1 < standards.length ? standards[index + 1] : null
  const subRanks = STRENGTH_SUB_RANKS[index]

  // Monarch has no ceiling; each sub-rank is a further 10% of the tier floor.
  const band = nextFloor !== null ? (nextFloor - tierFloor) / subRanks : tierFloor * 0.10

  // The epsilon is load-bearing: these thresholds are decimals, so an exact
  // band boundary lands just below it in binary (1.20 - 1.00 is
  // 0.19999999999999996) and would report one sub-rank too low.
  const subRank = ratio < tierFloor
    ? 1
    : Math.min(subRanks, Math.floor(((ratio - tierFloor) / band) + 1e-9) + 1)

  return {
    tierName: STRENGTH_TIERS[index],
    tier: index + 1,
    subRank,
    subRanks,
    displayRank: `${STRENGTH_TIERS[index]} ${subRank}`,
    isMaxed: nextFloor === null && subRank >= subRanks
  }
}
