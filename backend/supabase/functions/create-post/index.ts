import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { dailyGoldKey } from '../_shared/gameDay.ts'
import { isJpeg } from '../_shared/imageBytes.ts'

// One award per author per game day (Asia/Manila), shared with moderate-post
// through the same idempotency key.
const DAILY_POST_GOLD = 10

const ALLOWED_TABS = ['fitness', 'food']
const MAX_CONTENT_LENGTH = 1000
const MAX_TITLE_LENGTH = 100
// ~2MB decoded. The client always re-encodes to an 800px JPEG (well under
// this), so the cap and the bucket's own 2MB limit are only backstops.
const MAX_IMAGE_BASE64_LENGTH = 2_800_000
const MAX_INGREDIENTS_LENGTH = 1000
const MAX_NUTRIENT_G = 2000
const MAX_CALORIES = 10000

function isPositiveFinite(n: unknown, max: number): n is number {
  return typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= max
}

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

  if (!(await checkRateLimit(user.id, 'create_post', 10, 3600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const tab = typeof body.tab === 'string' ? body.tab.trim() : ''
  const content = typeof body.content === 'string' ? body.content.trim() : ''
  const title = typeof body.title === 'string' ? body.title.trim() : ''
  const imageBase64 = typeof body.image_base64 === 'string' ? body.image_base64.trim() : ''
  const ingredients = typeof body.ingredients === 'string' ? body.ingredients.trim() : ''

  const errors: string[] = []
  if (!ALLOWED_TABS.includes(tab)) errors.push(`tab must be one of: ${ALLOWED_TABS.join(', ')}`)
  if (!content) errors.push('content is required')
  if (content.length > MAX_CONTENT_LENGTH) errors.push(`content must be ${MAX_CONTENT_LENGTH} characters or fewer`)
  if (title.length > MAX_TITLE_LENGTH) errors.push(`title must be ${MAX_TITLE_LENGTH} characters or fewer`)
  if (imageBase64.length > MAX_IMAGE_BASE64_LENGTH) errors.push('Image too large')
  if (ingredients.length > MAX_INGREDIENTS_LENGTH) errors.push(`ingredients must be ${MAX_INGREDIENTS_LENGTH} characters or fewer`)

  // Nutrition facts are only meaningful — and only required — on a food
  // post; a fitness post never carries them, regardless of what's sent.
  // This mirrors the DB constraint (gymmunity_posts_food_requires_nutrients)
  // rather than replacing it — the constraint is what actually makes "food
  // posts need nutrients" true even if this function had a bug.
  let calories: number | null = null
  let protein: number | null = null
  let carbs: number | null = null
  let fat: number | null = null
  if (tab === 'food') {
    calories = Number(body.calories)
    protein = Number(body.protein)
    carbs = Number(body.carbs)
    fat = Number(body.fat)
    if (!isPositiveFinite(calories, MAX_CALORIES)) errors.push(`calories is required for a food post and must be between 0 and ${MAX_CALORIES}`)
    if (!isPositiveFinite(protein, MAX_NUTRIENT_G)) errors.push(`protein is required for a food post and must be between 0 and ${MAX_NUTRIENT_G}`)
    if (!isPositiveFinite(carbs, MAX_NUTRIENT_G)) errors.push(`carbs is required for a food post and must be between 0 and ${MAX_NUTRIENT_G}`)
    if (!isPositiveFinite(fat, MAX_NUTRIENT_G)) errors.push(`fat is required for a food post and must be between 0 and ${MAX_NUTRIENT_G}`)
  }

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // Images are uploaded here with the service-role client, never via a
  // client-supplied URL — same reasoning as everywhere else in this app:
  // the client's job is to hand over bytes, not to be trusted about where
  // they end up. Decode failures fail the whole post rather than silently
  // dropping the image the user thought they were attaching.
  let imageUrl: string | null = null
  if (imageBase64) {
    let bytes: Uint8Array
    try {
      bytes = Uint8Array.from(atob(imageBase64), c => c.charCodeAt(0))
    } catch {
      return new Response(JSON.stringify({ success: false, error: 'Invalid image data' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    // The bucket is public and the post isn't moderated yet: store real JPEGs
    // only, so it can never host arbitrary files under our domain.
    if (!isJpeg(bytes)) {
      return new Response(JSON.stringify({ success: false, error: 'Images must be photos (JPEG).' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    const path = `${user.id}/${crypto.randomUUID()}.jpg`
    const { error: uploadError } = await admin.storage
      .from('gymmunity-images')
      .upload(path, bytes, { contentType: 'image/jpeg' })

    if (uploadError) {
      return new Response(JSON.stringify({ success: false, error: `Image upload failed: ${uploadError.message}` }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    imageUrl = admin.storage.from('gymmunity-images').getPublicUrl(path).data.publicUrl
  }

  // No auto-moderation heuristic exists yet (out of scope for this pass —
  // see moderate-post for the manual admin path), so every post lands as
  // 'approved' — matching the column default — and is immediately eligible
  // for the daily gold award below. When a real flagging heuristic gets
  // built, route it to insert with status: 'pending' instead; moderate-post
  // already handles the gold-on-approval transition for that case.
  const { data: post, error } = await admin
    .from('gymmunity_posts')
    .insert({
      user_id: user.id, tab, content, title: title || null, image_url: imageUrl,
      ingredients: ingredients || null, calories, protein, carbs, fat
    })
    .select()
    .single()

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // One award per author per day, enforced by the idempotency key rather than
  // a count-then-insert that two simultaneous posts could both pass. The key
  // is shared with moderate-post, so a post approved later cannot pay a
  // second time for the same day.
  let goldAwarded = 0
  if (post.status === 'approved') {
    const { data: goldResult, error: goldError } = await admin.rpc('award_gold', {
      p_user_id: user.id,
      p_amount: DAILY_POST_GOLD,
      p_reason: 'daily_community_post',
      p_source_id: post.id,
      p_idempotency_key: dailyGoldKey('daily_community_post', user.id)
    })
    if (goldError) console.error('[create-post] gold award failed:', goldError.message)
    goldAwarded = goldResult?.awarded ? DAILY_POST_GOLD : 0
  }

  return new Response(JSON.stringify({ success: true, post, gold_awarded: goldAwarded }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
