// The nine specializations, in one place.
//
// This exists because the list was previously hardcoded in FIVE independent
// copies: ALLOWED_FOCUS_TYPES in register, update-profile and leaderboard, plus
// FOCUS_TYPES arrays in Signup.jsx and ProfilePage.jsx. Nothing tied them
// together, and `users.focus_type` had no CHECK constraint, so a single missed
// copy could write a focus_type with no rank ladder behind it — after which
// the user's rank silently stopped moving with no error anywhere.
//
// The database now carries a matching CHECK constraint on users.focus_type and
// user_specialization_xp.focus_type. If you add a specialization here you must
// also add it in that constraint AND seed its eight rank_thresholds rows, or
// log_workout_and_progress will raise MISSING_RANK_LADDER.

export const SPECIALIZATIONS = [
  'hybrid',
  'powerlifter',
  'cali',
  'aesthetic',
  'weightlifter',
  'strongman',
  'tactical',
  'hypertrophy',
  'lifestyle'
] as const

export type Specialization = typeof SPECIALIZATIONS[number]

export const DEFAULT_SPECIALIZATION: Specialization = 'hybrid'

export function isSpecialization(value: unknown): value is Specialization {
  return typeof value === 'string' && (SPECIALIZATIONS as readonly string[]).includes(value)
}

/** Human-readable list for validation error messages. */
export function specializationList(): string {
  return SPECIALIZATIONS.join(', ')
}

// A path may only be changed after this long, so that specialization means a
// training commitment rather than a per-workout XP optimisation.
export const SPECIALIZATION_LOCK_DAYS = 30

/**
 * Whether a user may switch away from their current path yet.
 * `startedAt` is users.specialization_started_at.
 */
export function specializationSwitchState(startedAt: string | null, now: Date = new Date()) {
  if (!startedAt) return { canSwitch: true, daysRemaining: 0 }

  const started = new Date(startedAt)
  if (Number.isNaN(started.getTime())) return { canSwitch: true, daysRemaining: 0 }

  const msElapsed = now.getTime() - started.getTime()
  const daysElapsed = Math.floor(msElapsed / 86_400_000)
  const daysRemaining = Math.max(0, SPECIALIZATION_LOCK_DAYS - daysElapsed)

  return { canSwitch: daysRemaining === 0, daysRemaining }
}
