import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'
import { hasPermission } from '../_shared/permissions.ts'
import { recordAdminAction } from '../_shared/audit.ts'

// Opening, closing and cancelling Dungeon events. Admin only.
//
//   GET                              every event, drafts included
//   POST { action: 'create', … }     a draft, invisible to players
//   POST { action: 'open', … }       publish it for N hours
//   POST { action: 'cancel', … }     stop it and pay consolations
//   POST { action: 'delete', event_id }  remove a draft, closed or cancelled event
//
// Delete cascades to the event's runs, battles, clears, invites and reward
// pool, so a live ('open') event is refused: cancel it first, which pays the
// players their consolations, then delete it.
//
// The role is checked twice on purpose: here, so the UI gets a clean 403, and
// again inside every admin_* database function, so a forged request cannot
// open a Dungeon even if this layer were bypassed.

const RL_MAX = 40
const RL_WINDOW_SECONDS = 300

const MAX_HP = 100000
const MIN_HP = 50
const DIFFICULTIES = ['easy', 'medium', 'hard']

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function playerMessage(raw: string): string {
  const match = raw.match(/^[A-Z_]+:\s*(.+)$/s)
  return match ? match[1] : raw
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()

  const { data: profile } = await admin
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (!hasPermission(profile?.role, 'manage_dungeons')) {
    return json({ success: false, error: 'Only an admin can manage Dungeon events.' }, 403)
  }

  if (req.method === 'GET') {
    const { data, error } = await admin.rpc('admin_list_dungeon_events', { p_admin_id: user.id })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 400)
    return json(data, 200)
  }

  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  if (!(await checkRateLimit(user.id, 'admin_dungeons', RL_MAX, RL_WINDOW_SECONDS))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))

  if (body.action === 'delete') {
    if (!isUuid(body.event_id)) return json({ success: false, error: 'A valid event_id is required.' }, 400)
    const { data: event } = await admin
      .from('dungeon_events').select('id, name, status').eq('id', body.event_id).maybeSingle()
    if (!event) return json({ success: false, error: 'Dungeon not found.' }, 404)
    if (event.status === 'open') {
      return json({ success: false, error: 'This Dungeon is live. Cancel it first so players are compensated, then delete it.' }, 409)
    }
    const { error } = await admin.from('dungeon_events').delete().eq('id', event.id).neq('status', 'open')
    if (error) return json({ success: false, error: 'Could not delete the Dungeon.' }, 500)
    const auditRecorded = await recordAdminAction(admin, {
      actorUserId: user.id,
      action: 'dungeon.delete',
      targetType: 'dungeon_event',
      targetId: event.id,
      metadata: { name: event.name, status: event.status }
    })
    return json({ success: true, deleted: event.id, audit_recorded: auditRecorded }, 200)
  }

  let rpc: { name: string; args: Record<string, unknown> }

  if (body.action === 'create') {
    const name = typeof body.name === 'string' ? body.name.trim() : ''
    if (name.length < 2 || name.length > 80) {
      return json({ success: false, error: 'A Dungeon name of 2 to 80 characters is required.' }, 400)
    }

    const bossMaxHp = Number(body.boss_max_hp)
    if (!Number.isInteger(bossMaxHp) || bossMaxHp < MIN_HP || bossMaxHp > MAX_HP) {
      return json({ success: false, error: `boss_max_hp must be a whole number from ${MIN_HP} to ${MAX_HP}.` }, 400)
    }

    const difficulty = typeof body.difficulty === 'string' ? body.difficulty : 'medium'
    if (!DIFFICULTIES.includes(difficulty)) {
      return json({ success: false, error: `difficulty must be one of: ${DIFFICULTIES.join(', ')}.` }, 400)
    }

    const rewardXp = Number(body.reward_xp ?? 600)
    const rewardGold = Number(body.reward_gold ?? 90)
    if (!Number.isInteger(rewardXp) || rewardXp < 0 || rewardXp > 100000) {
      return json({ success: false, error: 'reward_xp must be a whole number from 0 to 100000.' }, 400)
    }
    if (!Number.isInteger(rewardGold) || rewardGold < 0 || rewardGold > 100000) {
      return json({ success: false, error: 'reward_gold must be a whole number from 0 to 100000.' }, 400)
    }

    // The threat rank is checked against threat_ranks inside the RPC, so a
    // new rank row needs no change here.
    rpc = {
      name: 'admin_create_dungeon_event',
      args: {
        p_admin_id: user.id,
        p_payload: {
          name,
          threat_rank: typeof body.threat_rank === 'string' ? body.threat_rank : 'C',
          boss_max_hp: bossMaxHp,
          difficulty,
          boss_name: typeof body.boss_name === 'string' && body.boss_name.trim() ? body.boss_name.trim() : name,
          boss_lore: typeof body.boss_lore === 'string' ? body.boss_lore.trim() || null : null,
          config: {
            reward_xp: rewardXp,
            reward_gold: rewardGold,
            open_to_all: body.open_to_all !== false,
            min_contribution_percent: Number(body.min_contribution_percent ?? 10),
            potions: {
              health_potion: body.allow_health !== false,
              revive_potion: body.allow_revive !== false,
              rest_potion: body.allow_rest !== false
            }
          }
        }
      }
    }

  } else if (body.action === 'open') {
    if (!isUuid(body.event_id)) return json({ success: false, error: 'A valid event_id is required.' }, 400)
    const hours = Number(body.duration_hours ?? 24)
    if (!Number.isFinite(hours) || hours < 1 || hours > 720) {
      return json({ success: false, error: 'duration_hours must be between 1 and 720.' }, 400)
    }
    rpc = {
      name: 'admin_open_dungeon_event',
      args: { p_admin_id: user.id, p_event_id: body.event_id, p_duration_hours: hours }
    }

  } else if (body.action === 'cancel') {
    if (!isUuid(body.event_id)) return json({ success: false, error: 'A valid event_id is required.' }, 400)
    rpc = {
      name: 'admin_cancel_dungeon_event',
      args: { p_admin_id: user.id, p_event_id: body.event_id }
    }

  } else if (body.action === 'set_pool') {
    if (!isUuid(body.event_id)) return json({ success: false, error: 'A valid event_id is required.' }, 400)
    if (!Array.isArray(body.entries)) {
      return json({ success: false, error: 'entries must be an array.' }, 400)
    }
    if (body.entries.length > 20) {
      return json({ success: false, error: 'A reward pool holds at most 20 entries.' }, 400)
    }
    // The collectible key and the weights are validated inside the RPC
    // against the catalogue, so a new collectible needs no change here.
    rpc = {
      name: 'admin_set_dungeon_reward_pool',
      args: { p_admin_id: user.id, p_event_id: body.event_id, p_entries: body.entries }
    }

  } else {
    return json({
      success: false,
      error: 'action must be one of: create, open, cancel, set_pool, delete.'
    }, 400)
  }

  const { data, error } = await admin.rpc(rpc.name, rpc.args)
  if (error) return json({ success: false, error: playerMessage(error.message) }, 400)

  // deno-lint-ignore no-unused-vars
  const { p_admin_id, ...auditArgs } = rpc.args
  const auditRecorded = await recordAdminAction(admin, {
    actorUserId: user.id,
    action: `dungeon.${body.action}`,
    targetType: 'dungeon_event',
    targetId: typeof body.event_id === 'string' ? body.event_id : (data?.event_id ?? data?.event?.id ?? data?.id ?? null),
    metadata: auditArgs
  })

  return json(data && typeof data === 'object' && !Array.isArray(data) ? { ...data, audit_recorded: auditRecorded } : data, 200)
})
