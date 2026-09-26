import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { consentRequiredResponse } from '../_shared/consent.ts'
import { isUuid } from '../_shared/validation.ts'
import { gameDay } from '../_shared/gameDay.ts'
import { aiSafeSurveySummary, normalizeAnswers, normalizeLimits, type SurveyAnswers } from '../_shared/surveyRules.ts'
import { generatePlan, nextDifficultyStep, prescribe, weekOf, RATINGS, type LibraryRow, type PlanExercise } from '../_shared/planGenerator.ts'
import { PLAN_CATALOG } from '../_shared/planCatalog.ts'
import { completionRate, nextMonthAvailable, ratingCounts } from '../_shared/planState.ts'

// The training survey and the monthly plan made from it.
//
//   GET                                   survey status, current plan, the
//                                         exercise details it uses, notices
//   POST { action: 'submit_survey', answers, limits?, limits_notice_version? }
//        → saves the answers (and the opt-in areas), makes a new plan
//   POST { action: 'skip_survey' }        remembers "not now"
//   POST { action: 'set_day', plan_id, day, status: done|skipped|planned }
//   POST { action: 'rate', plan_id, session_key, day?, rating }
//        → too_easy / just_right / too_hard moves that session's level
//   POST { action: 'set_limits', areas, notice_version? }
//        → change or withdraw the areas to go easy on; remakes the plan
//   POST { action: 'next_month' }         a new month from the same answers
//   POST { action: 'ai_tips' }            optional AI tips about the plan
//
// The plan itself is made by _shared/planGenerator.ts from the answers, the
// path's affinity weights, the imported RepDB fields and the camera list.
// Areas to go easy on only affect which exercises are allowed; they are never
// sent to the AI.

const RL_READ_MAX = 120
const RL_WRITE_MAX = 60
const RL_WINDOW_SECONDS = 600
const RL_TIPS_MAX = 10
const IMAGE_LINK_SECONDS = 3600
const MEDIA_BUCKET = 'exercise-media'

const OLLAMA_URL = Deno.env.get('OLLAMA_URL') ?? 'http://localhost:11434'
const OLLAMA_MODEL = Deno.env.get('OLLAMA_MODEL') ?? 'llama3.2'
const OLLAMA_SECRET = Deno.env.get('OLLAMA_SECRET') ?? ''
const AI_TIMEOUT_MS = 30_000

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1].charAt(0).toUpperCase() + match[1].slice(1) : 'Something went wrong. Try again.'
}
const isDay = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)

// deno-lint-ignore no-explicit-any
type Admin = any

async function loadState(admin: Admin, userId: string) {
  const [survey, limits, plan] = await Promise.all([
    admin.from('training_surveys').select('status, answers, updated_at').eq('user_id', userId).maybeSingle(),
    admin.from('training_limits').select('areas, updated_at').eq('user_id', userId).maybeSingle(),
    admin.from('training_plans').select('*').eq('user_id', userId).eq('status', 'active').maybeSingle()
  ])
  let days: unknown[] = []
  let ratings: unknown[] = []
  if (plan.data) {
    const [d, r] = await Promise.all([
      admin.from('training_plan_days').select('day, session_key, status').eq('plan_id', plan.data.id).order('day'),
      admin.from('training_plan_feedback').select('day, session_key, rating, level_after, created_at').eq('plan_id', plan.data.id).order('created_at')
    ])
    days = d.data ?? []
    ratings = r.data ?? []
  }
  return { survey: survey.data, limits: limits.data, plan: plan.data, days, ratings }
}

async function makePlan(admin: Admin, userId: string, answers: SurveyAnswers, limits: string[], difficultyStep: number) {
  const { data: profile } = await admin.from('users').select('focus_type').eq('id', userId).single()
  const focusType = profile?.focus_type ?? 'hybrid'
  const names = PLAN_CATALOG.map(e => e.name)
  const [affinityRes, libraryRes, cameraRes] = await Promise.all([
    admin.from('specialization_affinity').select('match_value, multiplier')
      .eq('focus_type', focusType).eq('match_type', 'exercise'),
    admin.from('exercise_library').select('exercise, difficulty, tags').in('exercise', names),
    admin.from('game_config').select('value').eq('key', 'camera_trackable').maybeSingle()
  ])
  const affinity = Object.fromEntries((affinityRes.data ?? []).map((r: { match_value: string; multiplier: number }) => [r.match_value, Number(r.multiplier)]))
  const library: Record<string, LibraryRow> = Object.fromEntries(
    (libraryRes.data ?? []).map((r: { exercise: string; difficulty: string; tags: string[] }) => [r.exercise, { difficulty: r.difficulty, tags: r.tags }]))
  const cameraExercises = Array.isArray(cameraRes.data?.value) ? cameraRes.data.value : []

  const plan = generatePlan({
    answers, limits, focusType, startDate: gameDay(), seed: userId,
    affinity, library, cameraExercises, difficultyStep
  })
  const { error } = await admin.rpc('replace_active_plan', { p_user_id: userId, p_plan: plan })
  if (error) throw new Error(error.message)
}

// Details for the exercises in a plan: RepDB fields + signed image links.
async function exerciseDetails(admin: Admin, plan: { sessions: { exercises: { exercise: string; easier?: string; harder?: string }[] }[] } | null) {
  if (!plan) return {}
  const names = [...new Set(plan.sessions.flatMap(s => s.exercises.flatMap(x => [x.exercise, x.easier, x.harder]).filter(Boolean)))] as string[]
  const { data } = await admin.from('exercise_library')
    .select('exercise, name_en, description_en, difficulty, equipment, primary_muscles, secondary_muscles, instructions_en, tips_en, image_start, image_peak')
    .in('exercise', names)
  const rows = data ?? []
  const paths = rows.flatMap((r: { image_start: string | null; image_peak: string | null }) => [r.image_start, r.image_peak]).filter(Boolean)
  const signed = new Map<string, string>()
  if (paths.length > 0) {
    const { data: links } = await admin.storage.from(MEDIA_BUCKET).createSignedUrls(paths, IMAGE_LINK_SECONDS)
    for (const l of links ?? []) if (l.signedUrl && l.path) signed.set(l.path, l.signedUrl)
  }
  return Object.fromEntries(rows.map((r: Record<string, unknown>) => {
    const { image_start, image_peak, ...rest } = r
    return [r.exercise, {
      ...rest,
      image_start: image_start ? signed.get(image_start as string) ?? null : null,
      image_peak: image_peak ? signed.get(image_peak as string) ?? null : null
    }]
  }))
}

// Each training day's actual workout: the session's exercises at that day's
// week (ramp / deload) and the session's current difficulty level. Resolved
// here so the app only displays it — the rules live in one place.
type StoredSession = { key: string; name: string; focus: string; level: number; exercises: PlanExercise[] }
function resolveDays(plan: { start_date: string; sessions: StoredSession[] }, days: { day: string; session_key: string | null; status: string }[]) {
  const byKey = new Map(plan.sessions.map(s => [s.key, s]))
  return days.map(d => {
    const session = d.session_key ? byKey.get(d.session_key) : null
    if (!session) return { ...d, week: weekOf(plan.start_date, d.day), workout: null }
    const week = weekOf(plan.start_date, d.day)
    return {
      ...d,
      week,
      session_name: session.name,
      level: session.level ?? 0,
      workout: session.exercises.map(x => prescribe(x, week, session.level ?? 0))
    }
  })
}

async function stateResponse(admin: Admin, userId: string) {
  const state = await loadState(admin, userId)
  const [{ data: notice }, details] = await Promise.all([
    admin.rpc('get_current_notices'),
    exerciseDetails(admin, state.plan)
  ])
  const today = gameDay()
  return json({
    success: true,
    today,
    survey: state.survey ? { status: state.survey.status, answers: state.survey.answers, updated_at: state.survey.updated_at } : null,
    limits: state.limits?.areas ?? [],
    limits_notice: notice?.training_limits ?? null,
    plan: state.plan ? {
      id: state.plan.id,
      start_date: state.plan.start_date,
      end_date: state.plan.end_date,
      difficulty_step: state.plan.difficulty_step,
      sessions: state.plan.sessions,
      notes: state.plan.notes,
      days: resolveDays(state.plan, state.days as { day: string; session_key: string | null; status: string }[]),
      ratings: state.ratings,
      next_month_available: nextMonthAvailable(state.plan.end_date, today)
    } : null,
    exercises: details,
    credit: { text: 'Exercise data by RepDB (repdb.co)', url: 'https://repdb.co' }
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'GET' && req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  const admin = getAdminClient()

  if (req.method === 'GET') {
    if (!(await checkRateLimit(user.id, 'training_plan_read', RL_READ_MAX, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)
    return stateResponse(admin, user.id)
  }

  if (!(await checkRateLimit(user.id, 'training_plan_write', RL_WRITE_MAX, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)
  const body = await req.json().catch(() => ({}))

  try {
    if (body.action === 'submit_survey') {
      const checked = normalizeAnswers(body.answers)
      if (!checked.ok) return json({ success: false, error: checked.errors[0], errors: checked.errors }, 400)
      const limits = normalizeLimits(body.limits)
      if (!limits.ok) return json({ success: false, error: limits.error }, 400)

      // Opt-in areas are stored (or withdrawn) through the consent RPC. An
      // answer that doesn't mention them leaves an existing opt-in alone.
      if (body.limits !== undefined) {
        const current = await admin.from('training_limits').select('areas').eq('user_id', user.id).maybeSingle()
        if (limits.limits.length > 0 || current.data) {
          const { error } = await admin.rpc('set_training_limits', {
            p_user_id: user.id,
            p_areas: limits.limits.length > 0 ? limits.limits : null,
            p_notice_version: body.limits_notice_version ?? null
          })
          if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
        }
      }
      const { error: surveyError } = await admin.from('training_surveys').upsert({
        user_id: user.id, status: 'completed', answers: checked.answers, updated_at: new Date().toISOString()
      })
      if (surveyError) return json({ success: false, error: 'Could not save your answers.' }, 500)

      const { data: stored } = await admin.from('training_limits').select('areas').eq('user_id', user.id).maybeSingle()
      await makePlan(admin, user.id, checked.answers, stored?.areas ?? [], 0)
      return stateResponse(admin, user.id)
    }

    if (body.action === 'skip_survey') {
      // "Not now" never overwrites answers the user already gave.
      const { data: existing } = await admin.from('training_surveys').select('status').eq('user_id', user.id).maybeSingle()
      if (!existing) {
        const { error } = await admin.from('training_surveys').insert({ user_id: user.id, status: 'skipped', answers: null })
        if (error) return json({ success: false, error: 'Could not save that.' }, 500)
      }
      return json({ success: true })
    }

    if (body.action === 'set_day') {
      if (!isUuid(body.plan_id) || !isDay(body.day)) return json({ success: false, error: 'A plan and a day are required.' }, 400)
      const { data, error } = await admin.rpc('set_plan_day_status', {
        p_user_id: user.id, p_plan_id: body.plan_id, p_day: body.day, p_status: body.status
      })
      if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
      return json({ success: true, day: data })
    }

    if (body.action === 'rate') {
      if (!isUuid(body.plan_id) || typeof body.session_key !== 'string') return json({ success: false, error: 'A plan and a session are required.' }, 400)
      if (!RATINGS.includes(body.rating)) return json({ success: false, error: 'Rate it too easy, just right or too hard.' }, 400)
      if (body.day !== undefined && body.day !== null && !isDay(body.day)) return json({ success: false, error: 'Invalid day.' }, 400)
      const { data, error } = await admin.rpc('rate_plan_session', {
        p_user_id: user.id, p_plan_id: body.plan_id, p_session_key: body.session_key,
        p_day: body.day ?? null, p_rating: body.rating
      })
      if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
      return json({ success: true, result: data })
    }

    if (body.action === 'set_limits') {
      const limits = normalizeLimits(body.areas)
      if (!limits.ok) return json({ success: false, error: limits.error }, 400)
      const { error } = await admin.rpc('set_training_limits', {
        p_user_id: user.id,
        p_areas: limits.limits.length > 0 ? limits.limits : null,
        p_notice_version: body.notice_version ?? null
      })
      if (error) return json({ success: false, error: playerMessage(error.message) }, 409)
      // The plan must follow the new areas straight away.
      const { data: survey } = await admin.from('training_surveys').select('status, answers').eq('user_id', user.id).maybeSingle()
      const { data: plan } = await admin.from('training_plans').select('difficulty_step').eq('user_id', user.id).eq('status', 'active').maybeSingle()
      if (survey?.status === 'completed' && survey.answers) {
        const checked = normalizeAnswers(survey.answers)
        if (checked.ok) await makePlan(admin, user.id, checked.answers, limits.limits, plan?.difficulty_step ?? 0)
      }
      return stateResponse(admin, user.id)
    }

    if (body.action === 'next_month') {
      const state = await loadState(admin, user.id)
      if (state.survey?.status !== 'completed' || !state.survey.answers) {
        return json({ success: false, error: 'Take the training survey first.' }, 409)
      }
      const checked = normalizeAnswers(state.survey.answers)
      if (!checked.ok) return json({ success: false, error: 'Retake the training survey first.' }, 409)
      let step = 0
      if (state.plan) {
        const today = gameDay()
        if (!nextMonthAvailable(state.plan.end_date, today)) {
          return json({ success: false, error: 'Your next month opens in the last few days of this one.' }, 409)
        }
        step = nextDifficultyStep(state.plan.difficulty_step,
          completionRate(state.days as { day: string; session_key: string | null; status: string }[], today),
          ratingCounts(state.ratings as { rating: string }[]))
      }
      await makePlan(admin, user.id, checked.answers, state.limits?.areas ?? [], step)
      return stateResponse(admin, user.id)
    }

    if (body.action === 'ai_tips') {
      if (!(await checkRateLimit(user.id, 'training_plan_tips', RL_TIPS_MAX, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)
      const consentBlock = await consentRequiredResponse(user.id, 'ai_features', corsHeaders)
      if (consentBlock) return consentBlock
      const state = await loadState(admin, user.id)
      if (!state.plan || state.survey?.status !== 'completed') return json({ success: false, error: 'Make a plan first.' }, 409)
      const checked = normalizeAnswers(state.survey.answers)
      if (!checked.ok) return json({ success: false, error: 'Retake the training survey first.' }, 409)

      // Only what the AI notice lists: never the areas to go easy on.
      const summary = aiSafeSurveySummary(checked.answers)
      const sessions = (state.plan.sessions as { name: string; exercises: { label: string }[] }[])
        .map(s => `${s.name}: ${s.exercises.map(x => x.label).join(', ')}`).join('; ')
      const prompt = `You are a friendly strength coach. A user is following this 4-week plan: ${sessions}. ` +
        `Their goal is ${summary.goal.replace('_', ' ')}, experience ${summary.experience}, ${summary.daysPerWeek} training days a week, ` +
        `${summary.minutes}-minute sessions, equipment: ${summary.equipment}. Give exactly 3 short, practical tips for getting the most out of ` +
        `this plan (warm-up, progression, recovery or consistency). No medical advice. Format as a numbered list ("1. ...") with nothing before or after it.`

      try {
        const res = await fetch(`${OLLAMA_URL}/api/generate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-gym-key': OLLAMA_SECRET },
          body: JSON.stringify({ model: OLLAMA_MODEL, prompt, stream: false }),
          signal: AbortSignal.timeout(AI_TIMEOUT_MS)
        })
        if (!res.ok) throw new Error(String(res.status))
        const text = (await res.json())?.response?.trim()
        if (!text) throw new Error('empty')
        return json({ success: true, tips: text })
      } catch {
        return json({ success: false, error: 'The AI coach is offline right now. Your plan works without it — try tips again later.' }, 503)
      }
    }
  } catch (err) {
    console.error('[training-plan]', (err as Error).message)
    return json({ success: false, error: playerMessage((err as Error).message) }, 500)
  }

  return json({ success: false, error: 'Unknown action.' }, 400)
})
