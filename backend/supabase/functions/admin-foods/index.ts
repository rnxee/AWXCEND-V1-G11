import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission } from '../_shared/permissions.ts'
import { recordAdminAction } from '../_shared/audit.ts'
import { isUuid } from '../_shared/validation.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { changedFields, normalizeFoodInput, slugify } from '../_shared/foodRules.ts'

// Admin food editor (admins only, permission manage_foods).
//
//   GET ?q=&hidden=1&offset=                  list foods, hidden ones on request
//   POST { action: 'save', food_id?, expected_updated_at?, food, energy_confirmed? }
//                                             create (no food_id) or edit
//   POST { action: 'set_active', food_id, active }
//                                             hide / unhide
//   POST { action: 'delete', food_id }       remove for good
//
// Deleting keeps history intact: every meal log stores its own nutrition
// snapshot, and its food link is cleared (ON DELETE SET NULL). A food that
// market price data points at is refused (the database would RESTRICT it
// anyway) with a message to hide it instead. Hiding stays the reversible option.
//
// Input is validated by _shared/foodRules.ts first, for readable messages;
// admin_save_food re-checks the rules that matter for data integrity and
// adds the two that need the stored row (new provenance when nutrition
// values change, and no edits from an out-of-date copy). Every change is
// written to admin_audit_log after it succeeds.

// Lists, searches and writes share one budget; generous for real editing.
const RL_MAX = 120
const RL_WINDOW_SECONDS = 600

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1].charAt(0).toUpperCase() + match[1].slice(1) : raw
}

// Database refusals → HTTP status. Constraint violations only happen if the
// rules above and the migration disagree, so they are reported plainly.
function rpcFailure(message: string) {
  if (message.startsWith('STALE_EDIT') || message.startsWith('PROVENANCE_REQUIRED')) {
    return json({ success: false, error: playerMessage(message) }, 409)
  }
  if (message.startsWith('FOOD_NOT_FOUND')) return json({ success: false, error: playerMessage(message) }, 404)
  if (/^[A-Z_]+:/.test(message)) return json({ success: false, error: playerMessage(message) }, 400)
  if (message.includes('violates check constraint')) {
    return json({ success: false, error: 'The database refused these values as impossible. Check the numbers.' }, 400)
  }
  return json({ success: false, error: 'Could not save the food.' }, 500)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'GET' && req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()
  const { data: profile, error: profileError } = await admin.from('users').select('role').eq('id', user.id).single()
  if (profileError || !hasPermission(profile?.role, 'manage_foods')) {
    return json({ success: false, error: 'Admin access required' }, 403)
  }

  if (!(await checkRateLimit(user.id, 'admin_foods', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  if (req.method === 'GET') {
    const params = new URL(req.url).searchParams
    const query = (params.get('q') ?? '').slice(0, 60)
    const offset = Math.max(0, Math.min(10_000, Number.parseInt(params.get('offset') ?? '0', 10) || 0))
    const { data, error } = await admin.rpc('admin_list_foods', {
      p_query: query, p_include_hidden: params.get('hidden') === '1', p_limit: 30, p_offset: offset
    })
    if (error) return json({ success: false, error: 'Could not load foods.' }, 500)
    return json({ success: true, total: data.total, foods: data.items, offset })
  }

  const body = await req.json().catch(() => ({}))

  if (body.action === 'save') {
    const editing = body.food_id !== undefined && body.food_id !== null
    if (editing && !isUuid(body.food_id)) return json({ success: false, error: 'A valid food_id is required.' }, 400)
    if (editing && (typeof body.expected_updated_at !== 'string' || Number.isNaN(Date.parse(body.expected_updated_at)))) {
      return json({ success: false, error: 'Reopen the food and try again.' }, 400)
    }
    if (!body.food || typeof body.food !== 'object' || Array.isArray(body.food)) {
      return json({ success: false, error: 'Food details are missing.' }, 400)
    }

    const checked = normalizeFoodInput(body.food, { energyConfirmed: body.energy_confirmed === true })
    if (!checked.ok) {
      return json({
        success: false,
        error: checked.errors[0],
        errors: checked.errors,
        energy_expected: checked.energyExpected ?? null
      }, 400)
    }
    const { servings, ...food } = checked.food

    const { data, error } = await admin.rpc('admin_save_food', {
      p_food_id: editing ? body.food_id : null,
      p_expected_updated_at: editing ? body.expected_updated_at : null,
      p_food: editing ? food : { ...food, slug: slugify(food.name) },
      p_servings: servings
    })
    if (error) return rpcFailure(error.message)

    const saved = data.food
    const changed = data.created ? [] : changedFields(data.before ?? {}, checked.food)
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: data.created ? 'food.create' : 'food.update',
      targetType: 'food',
      targetId: saved.id,
      metadata: {
        slug: saved.slug,
        name: saved.name,
        source: saved.source,
        ...(data.created ? {} : { changed }),
        ...(checked.energy.mismatch ? { energy_mismatch_confirmed: true, energy_expected: checked.energy.expected } : {})
      }
    })
    return json({ success: true, created: data.created, food: saved, changed, audit_recorded: auditRecorded })
  }

  if (body.action === 'set_active') {
    if (!isUuid(body.food_id)) return json({ success: false, error: 'A valid food_id is required.' }, 400)
    if (typeof body.active !== 'boolean') return json({ success: false, error: 'active must be true or false.' }, 400)
    const { data, error } = await admin.rpc('admin_set_food_active', { p_food_id: body.food_id, p_active: body.active })
    if (error) return rpcFailure(error.message)
    let auditRecorded = true
    if (data.changed) {
      auditRecorded = await recordAdminAction(admin, {
        actorUserId: user.id,
        action: body.active ? 'food.unhide' : 'food.hide',
        targetType: 'food',
        targetId: data.food.id,
        metadata: { slug: data.food.slug, name: data.food.name }
      })
    }
    return json({ success: true, changed: data.changed, food: data.food, audit_recorded: auditRecorded })
  }

  if (body.action === 'delete') {
    if (!isUuid(body.food_id)) return json({ success: false, error: 'A valid food_id is required.' }, 400)
    const { data: food } = await admin.from('foods').select('id, slug, name').eq('id', body.food_id).maybeSingle()
    if (!food) return json({ success: false, error: 'Food not found.' }, 404)

    const { count: priceLinks } = await admin
      .from('market_commodities').select('id', { count: 'exact', head: true }).eq('food_id', food.id)
    if ((priceLinks ?? 0) > 0) {
      return json({
        success: false,
        error: 'Market price data uses this food, so it cannot be deleted. Hide it instead.'
      }, 409)
    }

    const { error } = await admin.from('foods').delete().eq('id', food.id)
    if (error) {
      return error.code === '23503'
        ? json({ success: false, error: 'Other data still uses this food. Hide it instead.' }, 409)
        : json({ success: false, error: 'Could not delete the food.' }, 500)
    }
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: 'food.delete',
      targetType: 'food',
      targetId: food.id,
      metadata: { slug: food.slug, name: food.name }
    })
    return json({ success: true, deleted: food.id, audit_recorded: auditRecorded })
  }

  return json({ success: false, error: 'action must be save, set_active or delete.' }, 400)
})
