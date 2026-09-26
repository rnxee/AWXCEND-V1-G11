// Escalating XP-per-level curve, independent of the rank system (rank_thresholds
// is 4 coarse per-focus-type tiers; this is a much finer-grained, game-style
// level counter layered on top of the same `xp` column — no new column needed,
// it's fully derived). Quadratic growth means each level costs more than the
// last: level 2 is one solid workout away, level 30 is a long grind — the
// classic "higher XP, harder to level up" curve.
const LEVEL_BASE = 50

// Cumulative XP required to REACH a given level (level 1 starts at 0 XP).
function xpForLevel(level: number): number {
  return Math.round(LEVEL_BASE * (level - 1) ** 2)
}

export function computeLevel(xp: number) {
  const safeXp = Math.max(0, xp || 0)
  let level = 1
  while (xpForLevel(level + 1) <= safeXp) level++

  const currentLevelXp = xpForLevel(level)
  const nextLevelXp = xpForLevel(level + 1)

  return {
    level,
    xpIntoLevel: safeXp - currentLevelXp,
    xpForNextLevel: nextLevelXp - currentLevelXp,
    xpToNextLevel: nextLevelXp - safeXp
  }
}
