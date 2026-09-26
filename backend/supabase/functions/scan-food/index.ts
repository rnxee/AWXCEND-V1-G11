import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { consentRequiredResponse } from '../_shared/consent.ts'

// Each call runs vision inference on the one self-hosted Ollama box. Unlimited
// calls are a cheap way to pin that machine, so this is throttled tighter than
// the CRUD endpoints — a real user scanning foods won't approach 20 in 5 min.
const RL_MAX = 20
const RL_WINDOW_SECONDS = 300

const OLLAMA_URL = Deno.env.get('OLLAMA_URL') ?? 'http://localhost:11434'
// A separate, deliberately small model from OLLAMA_MODEL (the text coach) —
// vision inference is heavier, and this only ever needs to name a food, not
// reason about it, so a lightweight model keeps this usable on modest
// hardware. See get-suggestions for the text-coaching model.
const OLLAMA_VISION_MODEL = Deno.env.get('OLLAMA_VISION_MODEL') ?? 'moondream'
const OLLAMA_SECRET = Deno.env.get('OLLAMA_SECRET') ?? ''

const MAX_IMAGE_BASE64_LENGTH = 4_000_000 // ~3MB decoded — the client downscales before upload, this is just a backstop

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

  if (!(await checkRateLimit(user.id, 'scan_food', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  // The photo goes to the self-hosted AI server: requires the AI notice.
  const consentBlock = await consentRequiredResponse(user.id, 'ai_features', corsHeaders)
  if (consentBlock) return consentBlock

  const body = await req.json().catch(() => ({}))
  const imageBase64 = typeof body.image_base64 === 'string' ? body.image_base64.trim() : ''

  if (!imageBase64) {
    return new Response(JSON.stringify({ success: false, error: 'image_base64 is required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  if (imageBase64.length > MAX_IMAGE_BASE64_LENGTH) {
    return new Response(JSON.stringify({ success: false, error: 'Image too large' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Scoped deliberately narrow — this identifies simple, single-item foods
  // (an egg, a banana, a bowl of rice), not multi-ingredient plates. The
  // resulting name only ever prefills the existing USDA search box, same as
  // typing it in by hand — it never bypasses user review before saving.
  const prompt = 'Identify the single food item in this image. Reply with ONLY its common name, 1-3 words, lowercase, nothing else. If you are not confident it is food, reply with "unknown".'

  let ollamaRes: Response
  try {
    ollamaRes = await fetch(`${OLLAMA_URL}/api/generate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-gym-key': OLLAMA_SECRET
      },
      body: JSON.stringify({
        model: OLLAMA_VISION_MODEL,
        prompt,
        images: [imageBase64],
        stream: false
      })
    })
  } catch {
    return new Response(JSON.stringify({ success: false, error: 'Could not reach the AI scanner. Is Ollama running?' }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  if (!ollamaRes.ok) {
    return new Response(JSON.stringify({ success: false, error: `Scanner responded with status ${ollamaRes.status}` }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const ollamaData = await ollamaRes.json()
  let foodName = (ollamaData?.response ?? '').trim().toLowerCase()
  // Small models occasionally wrap the answer in a sentence or punctuation
  // despite the prompt — strip anything past the first line/period and any
  // quoting, rather than rejecting a usable answer over formatting noise.
  foodName = foodName.split('\n')[0].split('.')[0].replace(/["'*]/g, '').trim()

  if (!foodName || foodName === 'unknown') {
    return new Response(JSON.stringify({ success: false, error: 'Could not identify a food in that photo. Try a clearer shot or enter it manually.' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, food_name: foodName }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
