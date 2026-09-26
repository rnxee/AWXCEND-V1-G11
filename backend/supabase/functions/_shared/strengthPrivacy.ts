// What a strength-leaderboard entry may reveal. Pure, so the rules are tested
// directly (src/lib/strengthPrivacy.test.js).
//
//  * Bodyweight is never sent for anyone but the viewer.
//  * Bodyweight multiples (relative e1RM) and strength tiers are sent only for
//    lifters who opted in to the relative board, and for the viewer. A tier is
//    defined on bodyweight multiples, so with a kilogram lift it narrows down
//    bodyweight too.

export type PrRow = {
  user_id: string
  weight_kg: number | string
  reps: number
  e1rm_kg: number | string
  relative_e1rm: number | string | null
  bodyweight_kg: number | string | null
  form_verified: boolean
  workout_source: string
  achieved_at: string
}

export type RankResolver = (relativeE1rm: number | string | null) => { displayRank: string; tier: string } | null

export function shapeStrengthEntry(
  row: PrRow,
  opts: { isSelf: boolean; relativeOptIn: boolean; resolveRank: RankResolver }
) {
  const showRelative = opts.isSelf || opts.relativeOptIn
  const rank = showRelative ? opts.resolveRank(row.relative_e1rm) : null
  return {
    e1rm_kg: Number(row.e1rm_kg),
    relative_e1rm: showRelative && row.relative_e1rm !== null ? Number(row.relative_e1rm) : null,
    weight_kg: Number(row.weight_kg),
    reps: row.reps,
    bodyweight_kg: opts.isSelf && row.bodyweight_kg !== null ? Number(row.bodyweight_kg) : null,
    form_verified: row.form_verified,
    workout_source: row.workout_source,
    achieved_at: row.achieved_at,
    strength_rank: rank?.displayRank ?? null,
    strength_tier: rank?.tier ?? null
  }
}
