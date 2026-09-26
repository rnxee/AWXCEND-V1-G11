// Builds a user's 4-week training plan from their survey answers. Pure and
// deterministic (same inputs + seed → same plan), so it's tested directly by
// src/lib/planGenerator.test.js and run server-side by the training-plan
// function, which supplies the database inputs (path affinity, the imported
// RepDB fields, the camera-trackable list).
//
// How a plan is made:
//   1. Allowed exercises = the plan catalog ∩ the user's equipment ∩ (for
//      every area to go easy on) exercises RepDB tags as safe for it.
//      Specialist lifts only for their own paths. No safety data → not safe.
//   2. The number of training days picks the split: 2–3 full body, 4
//      upper/lower, 5–6 push/pull/legs (+ a conditioning day for endurance
//      and fat-loss goals and the tactical / lifestyle paths).
//   3. Each session is a list of movement slots, cut to fit the session
//      length. Each slot takes the best allowed exercise: path affinity ×
//      camera preference × difficulty fit × variety, with a small seeded
//      tie-break. A slot with nothing allowed falls back to a related slot,
//      and if that fails it's dropped with a note — never an empty session.
//   4. Sets/reps (or seconds) come from the goal and experience. Weeks 1–3
//      ramp up, week 4 is a lighter deload — see prescribe().
//   5. Each session has a difficulty level the user moves with "too easy /
//      too hard" (adjustLevel); prescribe() applies it to the days still ahead.
import {
  AREA_SAFE_TAG, CATALOG_BY_NAME, EQUIPMENT_ACCESS, PLAN_CATALOG,
  type CatalogEntry, type Slot
} from './planCatalog.ts'
import type { SurveyAnswers } from './surveyRules.ts'

export const GENERATOR_VERSION = 1
export const PLAN_DAYS = 28
export const MIN_LEVEL = -3
export const MAX_LEVEL = 3
export const MAX_DIFFICULTY_STEP = 3

// ---------------------------------------------------------------------------
// Dates (plain YYYY-MM-DD strings, computed in UTC so the device timezone
// never shifts a day; the caller passes the game day, Asia/Manila)
// ---------------------------------------------------------------------------
const WEEKDAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const

function parseDay(day: string): number {
  const [y, m, d] = day.split('-').map(Number)
  return Date.UTC(y, m - 1, d)
}
function formatDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10)
}
export function weekdayOf(day: string): string {
  return WEEKDAY_KEYS[new Date(parseDay(day)).getUTCDay()]
}
export function addDays(day: string, n: number): string {
  return formatDay(parseDay(day) + n * 86_400_000)
}

// ---------------------------------------------------------------------------
// Seeded randomness (only ever a tie-break)
// ---------------------------------------------------------------------------
function hashString(s: string): number {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) }
  return h >>> 0
}
function mulberry32(seed: number) {
  let a = seed
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// ---------------------------------------------------------------------------
// Splits
// ---------------------------------------------------------------------------
type SessionTemplate = { focus: string; name: string; slots: Slot[] }

const FULL_BODY: SessionTemplate[] = [
  { focus: 'full', name: 'Full body A', slots: ['squat', 'push_h', 'pull_v', 'hinge', 'core', 'shoulders'] },
  { focus: 'full', name: 'Full body B', slots: ['hinge', 'push_v', 'pull_h', 'lunge', 'conditioning', 'arms'] },
  { focus: 'full', name: 'Full body C', slots: ['lunge', 'push_h', 'pull_h', 'squat', 'core', 'conditioning'] }
]
const UPPER_LOWER: SessionTemplate[] = [
  { focus: 'upper', name: 'Upper A', slots: ['push_h', 'pull_v', 'push_v', 'pull_h', 'arms', 'shoulders'] },
  { focus: 'lower', name: 'Lower A', slots: ['squat', 'hinge', 'lunge', 'core', 'conditioning', 'core'] },
  { focus: 'upper', name: 'Upper B', slots: ['push_v', 'pull_h', 'push_h', 'pull_v', 'shoulders', 'arms'] },
  { focus: 'lower', name: 'Lower B', slots: ['hinge', 'lunge', 'squat', 'core', 'conditioning', 'conditioning'] }
]
const PUSH_PULL_LEGS: SessionTemplate[] = [
  { focus: 'push', name: 'Push', slots: ['push_h', 'push_v', 'push_h', 'shoulders', 'arms', 'core'] },
  { focus: 'pull', name: 'Pull', slots: ['pull_v', 'pull_h', 'pull_v', 'arms', 'core', 'conditioning'] },
  { focus: 'legs', name: 'Legs', slots: ['squat', 'hinge', 'lunge', 'squat', 'core', 'conditioning'] }
]
const CONDITIONING_DAY: SessionTemplate =
  { focus: 'conditioning', name: 'Conditioning', slots: ['conditioning', 'lunge', 'core', 'conditioning', 'push_h', 'pull_h'] }

const CONDITIONING_PATHS = ['tactical', 'lifestyle']
// A path's own lifts go second in the sessions that train the whole body or legs.
const SPECIALIST_SLOT: Record<string, Slot> = { weightlifter: 'olympic', strongman: 'carry' }
const SPECIALIST_FOCUS = ['full', 'lower', 'legs']

function pickTemplates(answers: SurveyAnswers, focusType: string): SessionTemplate[] {
  const n = answers.days.length
  let templates: SessionTemplate[]
  if (n <= 3) templates = FULL_BODY.slice(0, n)
  else if (n === 4) templates = UPPER_LOWER
  else {
    templates = [...PUSH_PULL_LEGS]
    if (['endurance', 'fat_loss'].includes(answers.goal) || CONDITIONING_PATHS.includes(focusType)) {
      templates.push(CONDITIONING_DAY)
    }
  }
  const special = SPECIALIST_SLOT[focusType]
  if (!special) return templates
  return templates.map(t => SPECIALIST_FOCUS.includes(t.focus)
    ? { ...t, slots: [t.slots[0], special, ...t.slots.slice(1)] }
    : t)
}

// Minutes → exercises per session.
const EXERCISE_CAP: Record<number, number> = { 20: 3, 30: 4, 45: 5, 60: 6 }

const FALLBACK: Record<Slot, Slot[]> = {
  push_h: ['push_v'], push_v: ['push_h', 'shoulders'],
  pull_v: ['pull_h'], pull_h: ['pull_v'],
  squat: ['lunge', 'hinge'], lunge: ['squat', 'hinge'], hinge: ['squat', 'lunge'],
  arms: ['shoulders', 'core'], shoulders: ['arms', 'core'],
  core: ['conditioning'], conditioning: ['core'],
  carry: ['hinge'], olympic: ['hinge', 'squat']
}
const SLOT_LABEL: Record<Slot, string> = {
  push_h: 'chest press', push_v: 'overhead press', pull_v: 'vertical pull (like pull-ups)', pull_h: 'rowing pull',
  squat: 'squat', lunge: 'single-leg', hinge: 'hip hinge', arms: 'arm', shoulders: 'shoulder',
  core: 'core', conditioning: 'conditioning', carry: 'carry', olympic: 'Olympic lift'
}

// ---------------------------------------------------------------------------
// Volume
// ---------------------------------------------------------------------------
type Dose = { sets: number; reps: number }
const GOAL_VOLUME: Record<string, { main: Dose; accessory: Dose; seconds: number }> = {
  strength:  { main: { sets: 4, reps: 5 },  accessory: { sets: 3, reps: 8 },  seconds: 30 },
  muscle:    { main: { sets: 3, reps: 10 }, accessory: { sets: 3, reps: 12 }, seconds: 40 },
  endurance: { main: { sets: 3, reps: 12 }, accessory: { sets: 3, reps: 15 }, seconds: 45 },
  fat_loss:  { main: { sets: 3, reps: 12 }, accessory: { sets: 3, reps: 15 }, seconds: 40 },
  general:   { main: { sets: 3, reps: 10 }, accessory: { sets: 2, reps: 12 }, seconds: 30 }
}
const NEW_MAX_SETS = 3

export type PlanExercise = {
  exercise: string
  label: string
  metric: 'reps' | 'duration'
  role: 'main' | 'accessory'
  sets: number
  reps?: number
  seconds?: number
  easier: string | null
  harder: string | null
}

function baseDose(entry: CatalogEntry, answers: SurveyAnswers, step: number, isFirst: boolean) {
  const v = GOAL_VOLUME[answers.goal]
  const role = isFirst || entry.role === 'main' ? 'main' : 'accessory'
  let sets = v[role].sets
  if (answers.experience === 'experienced' && role === 'main') sets = Math.min(sets + 1, 5)
  if (answers.experience === 'new') sets = Math.min(sets, NEW_MAX_SETS)

  if (entry.metric === 'duration') {
    let seconds = v.seconds + (answers.experience === 'new' ? -10 : answers.experience === 'experienced' ? 15 : 0)
    // Conditioning holds (shadow boxing, cycling) run longer than static holds.
    if (entry.slot === 'conditioning') seconds *= 2
    return { role, sets, seconds: Math.max(20, seconds + 5 * step) }
  }
  let reps = v[role].reps
  if (entry.slot === 'conditioning') reps = answers.goal === 'strength' ? 15 : 20
  if (entry.name === 'burpee') reps = Math.ceil(reps / 2)
  return { role, sets, reps: reps + step }
}

// ---------------------------------------------------------------------------
// The plan
// ---------------------------------------------------------------------------
export type LibraryRow = { difficulty?: string | null; tags?: string[] | null }
export type PlanInput = {
  answers: SurveyAnswers
  limits: string[]
  focusType: string
  startDate: string
  seed: string
  affinity: Record<string, number>
  library: Record<string, LibraryRow>
  cameraExercises: string[]
  difficultyStep: number
}
export type PlanSession = { key: string; name: string; focus: string; level: number; exercises: PlanExercise[] }
export type Plan = {
  version: number
  startDate: string
  endDate: string
  difficultyStep: number
  sessions: PlanSession[]
  days: { day: string; session: string | null }[]
  notes: string[]
}

export function allowedExercises(input: Pick<PlanInput, 'answers' | 'limits' | 'focusType' | 'library'>): CatalogEntry[] {
  const access = EQUIPMENT_ACCESS[input.answers.equipment] ?? EQUIPMENT_ACCESS.bodyweight
  const safeTags = input.limits.map(a => AREA_SAFE_TAG[a]).filter(Boolean)
  return PLAN_CATALOG.filter(e => {
    if (!access.includes(e.equipment)) return false
    if (e.specialistFor && !e.specialistFor.includes(input.focusType)) return false
    if (safeTags.length > 0) {
      const tags = input.library[e.name]?.tags ?? []
      if (!safeTags.every(t => tags.includes(t))) return false
    }
    return true
  })
}

function difficultyFit(entry: CatalogEntry, answers: SurveyAnswers, library: Record<string, LibraryRow>) {
  const d = library[entry.name]?.difficulty
  if (answers.experience === 'new') return d === 'beginner' ? 1.1 : d === 'advanced' ? 0.5 : 1
  if (answers.experience === 'experienced') return d === 'advanced' ? 1.05 : 1
  return d === 'advanced' ? 0.85 : 1
}

export function generatePlan(input: PlanInput): Plan {
  const { answers, focusType, startDate } = input
  const step = Math.max(0, Math.min(MAX_DIFFICULTY_STEP, Math.trunc(input.difficultyStep || 0)))
  const rng = mulberry32(hashString(`${input.seed}|${startDate}|${GENERATOR_VERSION}`))
  const allowed = allowedExercises(input)
  const allowedNames = new Set(allowed.map(e => e.name))
  const camera = new Set(input.cameraExercises)
  const usedAnywhere = new Map<string, number>()
  const notes = new Set<string>()
  const cap = EXERCISE_CAP[answers.minutes] ?? 5

  const score = (e: CatalogEntry) => {
    let s = input.affinity[e.name] ?? 1
    if (answers.preferCamera && camera.has(e.name)) s *= 1.3
    s *= difficultyFit(e, answers, input.library)
    s *= Math.pow(0.75, usedAnywhere.get(e.name) ?? 0)
    return s
  }

  const variant = (name: string | undefined) => (name && allowedNames.has(name) ? name : null)

  const sessions: PlanSession[] = pickTemplates(answers, focusType).map((t, i) => {
    const key = String.fromCharCode(65 + i)
    const chosen: CatalogEntry[] = []
    for (const slot of t.slots) {
      if (chosen.length >= cap) break
      const isFirst = chosen.length === 0
      let pick: CatalogEntry | null = null
      const slots = [slot, ...FALLBACK[slot]]
      // A session opens with a main lift: look for one across the related
      // slots before settling for an accessory (e.g. a wall sit).
      const openerHasMain = isFirst && slots.some(s => allowed.some(e => e.slot === s && e.role === 'main'))
      for (const s of slots) {
        let candidates = allowed.filter(e => e.slot === s && !chosen.includes(e))
        if (openerHasMain) candidates = candidates.filter(e => e.role === 'main')
        if (candidates.length === 0) continue
        // Seeded jitter is drawn for every candidate in a fixed order, so
        // the plan stays deterministic.
        const scored = candidates.map(e => ({ e, v: score(e) * (1 + rng() * 0.04) }))
        scored.sort((a, b) => b.v - a.v || a.e.name.localeCompare(b.e.name))
        pick = scored[0].e
        break
      }
      if (!pick) {
        notes.add(`No ${SLOT_LABEL[slot]} exercise fits your equipment and the areas you asked to go easy on, so it was left out.`)
        continue
      }
      chosen.push(pick)
      usedAnywhere.set(pick.name, (usedAnywhere.get(pick.name) ?? 0) + 1)
    }
    // Never an empty session: fall back to the best of anything allowed.
    if (chosen.length === 0 && allowed.length > 0) {
      const best = [...allowed].sort((a, b) => score(b) - score(a) || a.name.localeCompare(b.name))[0]
      chosen.push(best)
    }
    const exercises: PlanExercise[] = chosen.map((e, idx) => {
      const dose = baseDose(e, answers, step, idx === 0)
      return {
        exercise: e.name,
        label: e.label,
        metric: e.metric,
        role: dose.role as 'main' | 'accessory',
        sets: dose.sets,
        ...(e.metric === 'duration' ? { seconds: dose.seconds } : { reps: dose.reps }),
        easier: variant(e.easier),
        harder: variant(e.harder)
      }
    })
    return { key, name: t.name, focus: t.focus, level: 0, exercises }
  })

  const days: Plan['days'] = []
  let next = 0
  for (let i = 0; i < PLAN_DAYS; i++) {
    const day = addDays(startDate, i)
    const training = (answers.days as string[]).includes(weekdayOf(day))
    days.push({ day, session: training && sessions.length > 0 ? sessions[next++ % sessions.length].key : null })
  }

  return {
    version: GENERATOR_VERSION,
    startDate,
    endDate: addDays(startDate, PLAN_DAYS - 1),
    difficultyStep: step,
    sessions,
    days,
    notes: [...notes]
  }
}

// ---------------------------------------------------------------------------
// What to actually do on a given week, at a given difficulty level
// ---------------------------------------------------------------------------
const DEFAULT_SECONDS = 30
const DEFAULT_REPS = 10

/**
 * The prescription for one plan exercise in week 1–4 at difficulty `level`.
 *   week 2: +1 rep (or +5 s) · week 3: main lifts +1 set, +1 rep (or +10 s)
 *   week 4: deload — 70% of the week-1 sets (or seconds)
 *   level:  ±1 rep (±10 s) per step, ±1 set every 2 steps
 *   at the level limit: swap to the easier / harder variant if there is one
 * Never below 1 set × 3 reps, or 10 seconds.
 */
export function prescribe(item: PlanExercise, week: number, level: number) {
  const lvl = Math.max(MIN_LEVEL, Math.min(MAX_LEVEL, Math.trunc(level)))
  const swapTo = lvl <= MIN_LEVEL ? item.easier : lvl >= MAX_LEVEL ? item.harder : null
  if (swapTo) {
    const entry = CATALOG_BY_NAME[swapTo]
    const metric = entry?.metric ?? item.metric
    const swapped: PlanExercise = {
      ...item,
      exercise: swapTo,
      label: entry?.label ?? swapTo,
      metric,
      ...(metric === 'duration'
        ? { seconds: item.seconds ?? DEFAULT_SECONDS, reps: undefined }
        : { reps: item.reps ?? DEFAULT_REPS, seconds: undefined }),
      easier: null,
      harder: null
    }
    return prescribe(swapped, week, 0)
  }

  const setDelta = Math.trunc(lvl / 2)
  let sets = item.sets + setDelta
  if (week === 3 && item.role === 'main') sets += 1
  if (week === 4) sets = Math.round((item.sets + setDelta) * 0.7)
  sets = Math.max(1, sets)

  if (item.metric === 'duration') {
    let seconds = (item.seconds ?? DEFAULT_SECONDS) + 10 * lvl
    if (week === 2) seconds += 5
    if (week === 3) seconds += 10
    if (week === 4) seconds = Math.round(seconds * 0.7)
    return { exercise: item.exercise, label: item.label, metric: item.metric, sets, seconds: Math.max(10, seconds) }
  }
  let reps = (item.reps ?? DEFAULT_REPS) + lvl
  if (week === 2 || week === 3) reps += 1
  return { exercise: item.exercise, label: item.label, metric: item.metric, sets, reps: Math.max(3, reps) }
}

/** Which plan week (1–4) a day falls in. */
export function weekOf(startDate: string, day: string): number {
  const diff = Math.round((parseDay(day) - parseDay(startDate)) / 86_400_000)
  return Math.max(1, Math.min(4, Math.floor(diff / 7) + 1))
}

const RATING_DELTA: Record<string, number> = { too_easy: 1, just_right: 0, too_hard: -1 }
export const RATINGS = Object.keys(RATING_DELTA)

/** One "too easy / just right / too hard" rating → the session's new level. */
export function adjustLevel(level: number, rating: string): number {
  if (!(rating in RATING_DELTA)) throw new Error(`Unknown rating: ${rating}`)
  return Math.max(MIN_LEVEL, Math.min(MAX_LEVEL, level + RATING_DELTA[rating]))
}

/**
 * Next month's difficulty step: one harder when at least 70% of the planned
 * days were done — unless most ratings said "too hard".
 */
export function nextDifficultyStep(step: number, completionRate: number, ratings: Partial<Record<string, number>>) {
  const hard = ratings.too_hard ?? 0
  const other = (ratings.too_easy ?? 0) + (ratings.just_right ?? 0)
  if (hard > other) return step
  if (completionRate >= 0.7) return Math.min(MAX_DIFFICULTY_STEP, step + 1)
  return step
}
