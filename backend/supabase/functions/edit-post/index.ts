import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { isJpeg } from '../_shared/imageBytes.ts'
import { isUuid, cleanText } from '../_shared/validation.ts'
import { postImagePath } from '../_shared/paging.ts'

const MAX_IMAGES = 10
const MAX_IMAGE_BASE64_LENGTH = 2_800_000
const MAX_CONTENT_LENGTH = 1000
const MAX_TITLE_LENGTH = 100
const MAX_INGREDIENTS_LENGTH = 1000
const MAX_NUTRIENT_G = 2000
const MAX_CALORIES = 10000

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function finiteNumber(value: unknown, max: number): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= max
}

function decodeJpeg(raw: unknown): Uint8Array | null {
  if (typeof raw !== 'string' || raw.length > MAX_IMAGE_BASE64_LENGTH) return null
  try {
    const bytes = Uint8Array.from(atob(raw), c => c.charCodeAt(0))
    return isJpeg(bytes) ? bytes : null
  } catch {
    return null
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)
  if (!(await checkRateLimit(user.id, 'edit_post', 30, 600))) return rateLimitResponse(corsHeaders)

  const body = await req.json().catch(() => ({}))
  const postId = typeof body.post_id === 'string' ? body.post_id.trim() : ''
  const content = cleanText(body.content)
  const title = cleanText(body.title)
  const ingredients = cleanText(body.ingredients)
  const keepIds = Array.isArray(body.keep_image_ids)
    ? body.keep_image_ids.filter((id: unknown): id is string => typeof id === 'string').map(id => id.trim())
    : []
  const keepLegacy = body.keep_legacy_image === true
  const newInputs = Array.isArray(body.new_images_base64)
    ? body.new_images_base64.filter((image: unknown): image is string => typeof image === 'string').map(image => image.trim())
    : []

  const errors: string[] = []
  if (!isUuid(postId)) errors.push('A valid post_id is required')
  if (!content) errors.push('content is required')
  if (content.length > MAX_CONTENT_LENGTH) errors.push(`content must be ${MAX_CONTENT_LENGTH} characters or fewer`)
  if (title.length > MAX_TITLE_LENGTH) errors.push(`title must be ${MAX_TITLE_LENGTH} characters or fewer`)
  if (ingredients.length > MAX_INGREDIENTS_LENGTH) errors.push(`ingredients must be ${MAX_INGREDIENTS_LENGTH} characters or fewer`)
  if (keepIds.some(id => !isUuid(id))) errors.push('keep_image_ids contains an invalid id')
  if (newInputs.length > MAX_IMAGES || newInputs.some(image => !image)) errors.push(`A post can contain at most ${MAX_IMAGES} images`)
  if (errors.length) return json({ success: false, errors }, 400)

  const admin = getAdminClient()
  const { data: post, error: postError } = await admin.from('gymmunity_posts')
    .select('id, user_id, tab, image_url')
    .eq('id', postId).eq('user_id', user.id).maybeSingle()
  if (postError || !post) return json({ success: false, error: 'Post not found.' }, 404)

  const { data: currentImages, error: imagesError } = await admin.from('gymmunity_post_images')
    .select('id, image_url, storage_path, sort_order')
    .eq('post_id', post.id).eq('user_id', user.id).order('sort_order', { ascending: true })
  if (imagesError) return json({ success: false, error: 'Could not load the post images.' }, 500)
  const current = currentImages ?? []
  const keepSet = new Set(keepIds)
  const retained = current.filter(image => keepSet.has(image.id))
  if (keepIds.length !== retained.length) return json({ success: false, error: 'One or more images do not belong to this post.' }, 403)

  const finalCount = retained.length + newInputs.length + (keepLegacy && post.image_url && current.length === 0 ? 1 : 0)
  if (finalCount > MAX_IMAGES) return json({ success: false, error: `A post can contain at most ${MAX_IMAGES} images` }, 400)

  let calories: number | null = null
  let protein: number | null = null
  let carbs: number | null = null
  let fat: number | null = null
  if (post.tab === 'food') {
    calories = Number(body.calories); protein = Number(body.protein); carbs = Number(body.carbs); fat = Number(body.fat)
    if (!finiteNumber(calories, MAX_CALORIES) || !finiteNumber(protein, MAX_NUTRIENT_G) ||
        !finiteNumber(carbs, MAX_NUTRIENT_G) || !finiteNumber(fat, MAX_NUTRIENT_G)) {
      return json({ success: false, error: 'Food posts need valid calories, protein, carbs and fat.' }, 400)
    }
  }

  const uploaded: { path: string; url: string }[] = []
  const cleanupUploaded = async () => {
    if (uploaded.length) await admin.storage.from('gymmunity-images').remove(uploaded.map(image => image.path))
  }
  for (const raw of newInputs) {
    const bytes = decodeJpeg(raw)
    if (!bytes) {
      await cleanupUploaded()
      return json({ success: false, error: 'Images must be valid JPEG photos.' }, 400)
    }
    const path = `${user.id}/${post.id}/${crypto.randomUUID()}.jpg`
    const { error: uploadError } = await admin.storage.from('gymmunity-images').upload(path, bytes, {
      contentType: 'image/jpeg', upsert: false,
    })
    if (uploadError) {
      await cleanupUploaded()
      return json({ success: false, error: `Image upload failed: ${uploadError.message}` }, 400)
    }
    uploaded.push({ path, url: admin.storage.from('gymmunity-images').getPublicUrl(path).data.publicUrl })
  }

  const removed = current.filter(image => !keepSet.has(image.id))
  const usedOrders = new Set(retained.map(image => image.sort_order))
  const newRows = uploaded.map(image => {
    let sort_order = 0
    while (usedOrders.has(sort_order)) sort_order += 1
    usedOrders.add(sort_order)
    return { post_id: post.id, user_id: user.id, image_url: image.url, storage_path: image.path, sort_order }
  })
  const legacyUrl = keepLegacy && post.image_url && current.length === 0 ? post.image_url : null
  const firstUrl = legacyUrl ?? retained[0]?.image_url ?? uploaded[0]?.url ?? null
  const restoreRemoved = async () => {
    if (removed.length) await admin.from('gymmunity_post_images').insert(removed.map(image => ({
      id: image.id, post_id: post.id, user_id: user.id, image_url: image.image_url,
      storage_path: image.storage_path, sort_order: image.sort_order,
    })))
  }
  const { error: removeError } = removed.length
    ? await admin.from('gymmunity_post_images').delete().in('id', removed.map(image => image.id)).eq('user_id', user.id)
    : { error: null }
  if (removeError) {
    await cleanupUploaded()
    return json({ success: false, error: 'Could not update the post images.' }, 500)
  }
  if (newRows.length) {
    const { error: insertError } = await admin.from('gymmunity_post_images').insert(newRows)
    if (insertError) {
      await restoreRemoved()
      await cleanupUploaded()
      return json({ success: false, error: `Image record failed: ${insertError.message}` }, 400)
    }
  }

  const { data: updated, error: updateError } = await admin.from('gymmunity_posts').update({
    content, title: title || null, ingredients: ingredients || null, calories, protein, carbs, fat, image_url: firstUrl,
  }).eq('id', post.id).eq('user_id', user.id).select().single()
  if (updateError || !updated) {
    if (newRows.length) await admin.from('gymmunity_post_images').delete().in('storage_path', uploaded.map(image => image.path))
    await restoreRemoved()
    await cleanupUploaded()
    return json({ success: false, error: updateError?.message ?? 'Could not update the post.' }, 400)
  }

  const removedPaths = removed.map(image => image.storage_path)
  const legacyPath = current.length === 0 && !keepLegacy ? postImagePath(post.image_url) : null
  if (legacyPath && legacyPath.startsWith(`${user.id}/`)) removedPaths.push(legacyPath)
  if (removedPaths.length) await admin.storage.from('gymmunity-images').remove(removedPaths)
  return json({ success: true, post: updated })
})
