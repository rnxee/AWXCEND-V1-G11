// The training survey shown after login, and how its answers are checked.
// Pure, so src/lib/surveyRules.test.js can import it directly. The server
// (training-plan) is the only place answers are accepted; the survey screen
// shows the same options but decides nothing.
//
// "Areas to go easy on" are health information. They're asked only after an
// explicit opt-in (consent type `training_limits`), are used only to leave
// matching exercises out of the plan, and are never sent to an AI.

export const GOALS = ['muscle', 'fat_loss', 'strength', 'endurance', 'general'] as const
export const EXPERIENCE = ['new', 'some', 'experienced'] as const
export const SESSION_MINUTES = [20, 30, 45, 60] as const
export const EQUIPMENT = ['bodyweight', 'dumbbells', 'gym'] as const
export const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const
export const LIMIT_AREAS = ['knees', 'lower_back', 'shoulders'] as const

export const MIN_DAYS = 2
export const MAX_DAYS = 6

export type SurveyAnswers = {
  goal: (typeof GOALS)[number]
  experience: (typeof EXPERIENCE)[number]
  days: (typeof WEEKDAYS)[number][]
  minutes: (typeof SESSION_MINUTES)[number]
  equipment: (typeof EQUIPMENT)[number]
  preferCamera: boolean
}

const has = <T extends readonly unknown[]>(list: T, v: unknown): v is T[number] =>
  (list as readonly unknown[]).includes(v)

/**
 * Checks and cleans the survey answers. Training days come back in week
 * order (Mon → Sun) without duplicates. Returns the answers or every problem.
 */
export function normalizeAnswers(raw: unknown):
  { ok: true; answers: SurveyAnswers } | { ok: false; errors: string[] } {
  const r = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {}) as Record<string, unknown>
  const errors: string[] = []

  if (!has(GOALS, r.goal)) errors.push('Pick a goal.')
  if (!has(EXPERIENCE, r.experience)) errors.push('Pick your experience.')
  if (!has(EQUIPMENT, r.equipment)) errors.push('Pick the equipment you have.')

  const minutes = typeof r.minutes === 'string' ? Number(r.minutes) : r.minutes
  if (!has(SESSION_MINUTES, minutes)) errors.push('Pick a session length.')

  const rawDays = Array.isArray(r.days) ? r.days : []
  const days = WEEKDAYS.filter(d => rawDays.includes(d))
  if (rawDays.some(d => !has(WEEKDAYS, d))) errors.push('Training days must be days of the week.')
  if (days.length < MIN_DAYS || days.length > MAX_DAYS) {
    errors.push(`Pick ${MIN_DAYS} to ${MAX_DAYS} training days a week — rest days matter too.`)
  }

  if (errors.length > 0) return { ok: false, errors }
  return {
    ok: true,
    answers: {
      goal: r.goal as SurveyAnswers['goal'],
      experience: r.experience as SurveyAnswers['experience'],
      days,
      minutes: minutes as SurveyAnswers['minutes'],
      equipment: r.equipment as SurveyAnswers['equipment'],
      preferCamera: r.preferCamera === true
    }
  }
}

/** Areas to go easy on: only known areas, no duplicates, in a fixed order. */
export function normalizeLimits(raw: unknown): { ok: true; limits: string[] } | { ok: false; error: string } {
  if (raw === null || raw === undefined) return { ok: true, limits: [] }
  if (!Array.isArray(raw)) return { ok: false, error: 'Areas to go easy on must be a list.' }
  if (raw.some(a => !has(LIMIT_AREAS, a))) return { ok: false, error: 'Unknown area to go easy on.' }
  return { ok: true, limits: LIMIT_AREAS.filter(a => raw.includes(a)) }
}

/**
 * What the optional AI tips may see. Never the areas to go easy on — they
 * are health information the user shared only for exercise selection.
 */
export function aiSafeSurveySummary(answers: SurveyAnswers) {
  return {
    goal: answers.goal,
    experience: answers.experience,
    daysPerWeek: answers.days.length,
    minutes: answers.minutes,
    equipment: answers.equipment
  }
}
