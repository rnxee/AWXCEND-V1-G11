import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { computeMacroTarget } from '../_shared/macroTargets.ts'
import { consentRequiredResponse } from '../_shared/consent.ts'

// Same self-hosted Ollama box as scan-food, same GPU-protection reasoning —
// each call is an LLM generation. Real users request coaching occasionally,
// not in bursts, so 20 per 5 minutes is generous while stopping a hammer.
const RL_MAX = 20
const RL_WINDOW_SECONDS = 300

const OLLAMA_URL = Deno.env.get('OLLAMA_URL') ?? 'http://localhost:11434'
const OLLAMA_MODEL = Deno.env.get('OLLAMA_MODEL') ?? 'llama3.2'
// Ollama runs on a home machine behind an ngrok tunnel, which is a public URL.
// The tunnel's traffic policy denies anything without this header, so the whole
// Ollama API (including /api/pull and /api/delete) isn't open to whoever finds it.
const OLLAMA_SECRET = Deno.env.get('OLLAMA_SECRET') ?? ''

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) {
    return new Response(JSON.stringify({ success: false, error: authError }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  if (!(await checkRateLimit(user.id, 'get_suggestions', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  // Profile-derived data goes to the self-hosted AI server: requires the AI notice.
  const consentBlock = await consentRequiredResponse(user.id, 'ai_features', corsHeaders)
  if (consentBlock) return consentBlock

  const admin = getAdminClient()

  const todayStart = new Date()
  todayStart.setUTCHours(0, 0, 0, 0)

  const [profileRes, logsRes, mealsRes] = await Promise.all([
    admin.from('users').select('rank, focus_type, weight_kg, height_cm, sex, age, goal').eq('id', user.id).single(),
    admin.from('workout_logs').select('exercise, rep_quality_score').eq('user_id', user.id).order('logged_at', { ascending: false }).limit(20),
    admin.from('fitrack_logs').select('calories, protein, carbs, fat, fiber, sugar').eq('user_id', user.id).gte('logged_at', todayStart.toISOString())
  ])

  if (profileRes.error) {
    return new Response(JSON.stringify({ success: false, error: profileRes.error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const logs = logsRes.data ?? []
  const avgQuality = logs.length
    ? (logs.reduce((sum, l) => sum + (l.rep_quality_score ?? 0), 0) / logs.length).toFixed(2)
    : 'N/A'
  const exercises = [...new Set(logs.map(l => l.exercise))].join(', ') || 'none logged yet'

  const meals = mealsRes.data ?? []
  const actual = meals.reduce((acc, m) => ({
    calories: acc.calories + (m.calories ?? 0),
    protein: acc.protein + (m.protein ?? 0),
    carbs: acc.carbs + (m.carbs ?? 0),
    fat: acc.fat + (m.fat ?? 0),
    fiber: acc.fiber + (m.fiber ?? 0),
    sugar: acc.sugar + (m.sugar ?? 0)
  }), { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0 })

  const { sex, age, goal, focus_type: focusType } = profileRes.data
  // Shared with budget-assistant so both screens show the same target.
  const macroTarget = computeMacroTarget(profileRes.data)

  const goalLabel = goal || `a typical ${focusType} goal`
  const nutritionBlock = macroTarget
    ? `Daily macro target (estimated from weight/height${age ? '/age' : ''}${sex ? '/sex' : ''}, moderately-active assumption, tuned for ${goalLabel}): ${macroTarget.calories} kcal, ${macroTarget.protein}g protein, ${macroTarget.carbs}g carbs, ${macroTarget.fat}g fat, ${macroTarget.fiber}g fiber, under ${macroTarget.sugar}g sugar. So far today the user has logged: ${Math.round(actual.calories)} kcal, ${Math.round(actual.protein)}g protein, ${Math.round(actual.carbs)}g carbs, ${Math.round(actual.fat)}g fat, ${Math.round(actual.fiber)}g fiber, ${Math.round(actual.sugar)}g sugar.`
    : 'The user has not set a weight/height yet, so no macro target could be calculated — encourage them to add it in their profile for personalized nutrition coaching.'

  const prompt = `You are a fitness and nutrition coach helping the user become a ${focusType} athlete${goal ? ` while trying to ${goal}` : ''}. They are rank ${profileRes.data.rank}, average rep quality: ${avgQuality}, recent exercises: ${exercises}. ${nutritionBlock} Give exactly 3 short, specific tips that explicitly tie back to helping them progress toward being a ${focusType} athlete${goal ? ` and reach their ${goal} goal` : ''} — mix exercise feedback and nutrition/macro guidance. Do not restate the raw numbers verbatim, coach on what to do about them.

Format the reply as a numbered list, one tip per line ("1. ...", "2. ...", "3. ..."), nothing before or after the list. In each tip, wrap only the single most important word or short phrase — the specific action or number to focus on — in **double asterisks**, e.g. "Add **10g more protein** at breakfast." Do not bold whole sentences, and do not use any other markdown.`

  let ollamaRes: Response
  try {
    ollamaRes = await fetch(`${OLLAMA_URL}/api/generate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-gym-key': OLLAMA_SECRET
      },
      body: JSON.stringify({ model: OLLAMA_MODEL, prompt, stream: false })
    })
  } catch {
    return new Response(JSON.stringify({ success: false, error: 'Could not reach Ollama. Is it running?' }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  if (!ollamaRes.ok) {
    return new Response(JSON.stringify({ success: false, error: `Ollama responded with status ${ollamaRes.status}` }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const ollamaData = await ollamaRes.json()
  const suggestionText = ollamaData?.response?.trim()

  if (!suggestionText) {
    return new Response(JSON.stringify({ success: false, error: 'No suggestion returned from AI service' }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  await admin.from('ai_suggestions').insert({
    user_id: user.id,
    suggestion_text: suggestionText
  })

  return new Response(JSON.stringify({
    suggestion_text: suggestionText,
    macro_target: macroTarget,
    macro_actual: macroTarget ? { calories: Math.round(actual.calories), protein: Math.round(actual.protein), carbs: Math.round(actual.carbs), fat: Math.round(actual.fat), fiber: Math.round(actual.fiber), sugar: Math.round(actual.sugar) } : null
  }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
