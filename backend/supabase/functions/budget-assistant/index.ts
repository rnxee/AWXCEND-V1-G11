import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { gameDay } from '../_shared/gameDay.ts'
import { computeMacroTarget } from '../_shared/macroTargets.ts'
import { hasPermission } from '../_shared/permissions.ts'
import { recordAdminAction } from '../_shared/audit.ts'
import {
  buildOverview,
  estimateMeal,
  parseEstimateItems,
  parseMoney,
  parsePriceNote,
  MAX_DAILY_BUDGET_PHP,
  MAX_PRICE_PHP,
  PRICE_OUTDATED_AFTER_DAYS,
  PROTEIN_COMPARISON_GRAMS,
  PROTEIN_SWAP_MIN_KCAL_SHARE
} from '../_shared/budgetMath.ts'
import type { CommodityRow } from '../_shared/budgetMath.ts'

// Budget-aware nutrition assistant — estimates, not financial or dietary advice.
//
//   GET                                              budget, protein target, and
//                                                    every item's price and
//                                                    calculated protein cost
//   POST { action: 'estimate', items: [{ commodity, amount }] }
//                                                    cost + nutrition of RAW
//                                                    bought amounts
//   POST { action: 'set_budget', daily_budget_php }  number, or null to clear
//   POST { action: 'set_price', commodity, price_php }  number, or null to clear
//   POST { action: 'set_reference_price', commodity, price_php, note }
//                                                    admins only (manage_foods):
//                                                    appends an admin-adjusted
//                                                    reference price for everyone
//
// All labelling happens here, not in the client: which price applies (the
// user's own, else the DA reference), whether nutrition can be calculated
// (only with a sourced inedible share), and whether a food is in the
// protein-swap comparison. Nothing is sent to an AI model.

const RL_MAX = 60
const RL_WINDOW_SECONDS = 300
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

// Database errors arrive as "CODE: human sentence".
function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'GET' && req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  if (!(await checkRateLimit(user.id, 'budget_assistant', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const admin = getAdminClient()
  const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {}

  // ---- writes -------------------------------------------------------------
  if (req.method === 'POST' && body.action === 'set_budget') {
    const { value, error } = parseMoney(body.daily_budget_php, MAX_DAILY_BUDGET_PHP)
    if (error) return json({ success: false, error: `Daily budget ${error}.` }, 400)
    const { data, error: dbError } = await admin.rpc('set_user_budget', { p_user_id: user.id, p_daily_budget_php: value })
    if (dbError) return json({ success: false, error: playerMessage(dbError.message) }, 400)
    return json({ success: true, budget: data })
  }

  if (req.method === 'POST' && body.action === 'set_price') {
    const slug = typeof body.commodity === 'string' ? body.commodity : ''
    if (!SLUG_RE.test(slug)) return json({ success: false, error: 'A valid commodity is required.' }, 400)
    const { value, error } = parseMoney(body.price_php, MAX_PRICE_PHP)
    if (error) return json({ success: false, error: `Price ${error}.` }, 400)
    const { data, error: dbError } = await admin.rpc('record_user_commodity_price', {
      p_user_id: user.id, p_commodity_slug: slug, p_price_php: value
    })
    if (dbError) {
      const status = /UNKNOWN_COMMODITY/.test(dbError.message) ? 400 : 500
      return json({ success: false, error: playerMessage(dbError.message) }, status)
    }
    return json({ success: true, price: data })
  }

  // The same permission as the admin food editor.
  const canAdjustPrices = async () => {
    const { data } = await admin.from('users').select('role').eq('id', user.id).single()
    return hasPermission(data?.role, 'manage_foods')
  }

  if (req.method === 'POST' && body.action === 'set_reference_price') {
    if (!(await canAdjustPrices())) return json({ success: false, error: 'Admin access required' }, 403)
    const slug = typeof body.commodity === 'string' ? body.commodity : ''
    if (!SLUG_RE.test(slug)) return json({ success: false, error: 'A valid commodity is required.' }, 400)
    // No clearing: a reference price is replaced by a newer one, never removed.
    const { value, error } = body.price_php === null ? { value: null, error: 'is required' } : parseMoney(body.price_php, MAX_PRICE_PHP)
    if (error) return json({ success: false, error: `Price ${error}.` }, 400)
    const note = parsePriceNote(body.note)
    if (note.error) return json({ success: false, error: `${note.error}.` }, 400)
    const { data, error: dbError } = await admin.rpc('admin_set_reference_price', {
      p_commodity_slug: slug, p_price_php: value, p_note: note.value, p_day: gameDay()
    })
    if (dbError) {
      const status = /UNKNOWN_COMMODITY/.test(dbError.message) ? 400 : 500
      return json({ success: false, error: playerMessage(dbError.message) }, status)
    }
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: 'price.adjust',
      targetType: 'commodity',
      targetId: null,
      metadata: {
        commodity: data.commodity, name: data.name, unit: data.unit,
        price_php: data.price_php, previous_price_php: data.previous_price_php, note: data.note
      }
    })
    return json({ success: true, price: data, audit_recorded: auditRecorded })
  }

  if (req.method === 'POST' && body.action !== 'estimate') {
    return json({ success: false, error: 'action must be estimate, set_budget, set_price or set_reference_price.' }, 400)
  }

  // ---- reads (GET, and POST estimate) -------------------------------------
  const [dataRes, profileRes] = await Promise.all([
    admin.rpc('get_budget_data', { p_user_id: user.id }),
    admin.from('users').select('weight_kg, height_cm, sex, age, goal, focus_type, role').eq('id', user.id).single()
  ])
  if (dataRes.error) return json({ success: false, error: dataRes.error.message }, 500)
  if (profileRes.error) return json({ success: false, error: profileRes.error.message }, 400)

  const rows = (dataRes.data?.commodities ?? []) as CommodityRow[]
  const dailyBudget = dataRes.data?.budget?.daily_budget_php ?? null
  const budget = dailyBudget === null ? null : {
    daily_php: Number(dailyBudget),
    // Display equivalent only: daily × 7.
    weekly_php: Math.round(Number(dailyBudget) * 7 * 100) / 100,
    updated_at: dataRes.data.budget.updated_at
  }
  const macroTarget = computeMacroTarget(profileRes.data)
  const proteinTarget = macroTarget
    ? { grams: macroTarget.protein, basis: 'Estimated from your profile (weight, height, age, sex, goal and path) — the same target as AI Suggestions.' }
    : null
  const today = gameDay()

  if (req.method === 'POST') {
    const bySlug = new Map(rows.map(r => [r.slug, r]))
    const { items, errors } = parseEstimateItems(body.items, bySlug)
    if (errors.length > 0) return json({ success: false, errors }, 400)
    return json({
      success: true,
      computed_at: new Date().toISOString(),
      today,
      budget,
      protein_target: proteinTarget,
      estimate: estimateMeal(items, bySlug, today, {
        dailyBudgetPhp: budget?.daily_php ?? null,
        proteinTargetG: proteinTarget?.grams ?? null
      })
    })
  }

  return json({
    success: true,
    today,
    budget,
    protein_target: proteinTarget,
    rules: {
      protein_swap_min_kcal_share: PROTEIN_SWAP_MIN_KCAL_SHARE,
      protein_comparison_grams: PROTEIN_COMPARISON_GRAMS,
      price_outdated_after_days: PRICE_OUTDATED_AFTER_DAYS
    },
    commodities: buildOverview(rows, today),
    can_adjust_prices: hasPermission(profileRes.data.role, 'manage_foods')
  })
})
