import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { isUuid } from '../_shared/validation.ts'

// Everything a player does inside a Dungeon.
//
//   GET                             open Dungeons, which are already cleared,
//                                   and any battle of theirs still live
//   POST { action: 'create' }       form a party in an event
//   POST { action: 'parties' }      forming parties they could join
//   POST { action: 'join' }         join a friend's forming party
//   POST { action: 'start' }        close entry and begin the fight
//   POST { action: 'state' }        the poll — also the presence heartbeat
//   POST { action: 'objective_start' }  stamp the moment tracking goes live
//   POST { action: 'submit' }       hand in a finished set, optionally against
//                                   a teammate's objective (an assist)
//   POST { action: 'ping' }         advisory progress, for the party display
//   POST { action: 'quit' }         walk out (terminal for that battle)
//
// Potions are not here: they go through the shop function's `use` action with
// context_type 'dungeon_run', so there is one place that spends an item.
//
// Nothing here decides an outcome. Damage, HP, contribution, deadlines and
// every reward are computed inside the database functions, which take the
// user id from the verified token below and never from the request body.

// A submit logs a real workout, so it shares log-workout's farming bucket —
// routing sets through a Dungeon buys a script no extra headroom.
const SUBMIT_RL = { action: 'log_workout', max: 40, windowSeconds: 300 }
// The state poll runs every few seconds by design; it gets its own generous
// bucket so a normal fight cannot rate-limit itself. Progress pings share it,
// since they are the same kind of chatter.
const STATE_RL = { action: 'dungeon_state', max: 250, windowSeconds: 300 }
const OTHER_RL = { action: 'dungeon_action', max: 60, windowSeconds: 300 }

const ALLOWED_SOURCES = ['camera', 'manual']
const MAX_ACHIEVED = 21600
const MAX_WEIGHT_KG = 500

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

// Database errors arrive as "CODE: human sentence". The code is for logs; the
// sentence is written to be shown to the player.
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

  if (req.method === 'GET') {
    const { data, error } = await admin.rpc('get_dungeon_events', { p_user_id: user.id })
    if (error) return json({ success: false, error: playerMessage(error.message) }, 400)
    return json(data, 200)
  }

  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  const body = await req.json().catch(() => ({}))
  const action = typeof body.action === 'string' ? body.action : ''

  const rl = action === 'submit'
    ? SUBMIT_RL
    : (action === 'state' || action === 'ping') ? STATE_RL : OTHER_RL
  if (!(await checkRateLimit(user.id, rl.action, rl.max, rl.windowSeconds))) {
    return rateLimitResponse(corsHeaders)
  }

  let rpc: { name: string; args: Record<string, unknown> }

  if (action === 'create') {
    if (!isUuid(body.event_id)) return json({ success: false, error: 'A valid event_id is required.' }, 400)
    rpc = { name: 'create_dungeon_battle', args: { p_user_id: user.id, p_event_id: body.event_id } }

  } else if (action === 'parties') {
    if (!isUuid(body.event_id)) return json({ success: false, error: 'A valid event_id is required.' }, 400)
    rpc = {
      name: 'get_joinable_dungeon_battles',
      args: { p_user_id: user.id, p_event_id: body.event_id }
    }

  } else if (action === 'start' || action === 'state' || action === 'objective_start'
             || action === 'quit' || action === 'join') {
    if (!isUuid(body.battle_id)) return json({ success: false, error: 'A valid battle_id is required.' }, 400)
    const names: Record<string, string> = {
      start: 'start_dungeon_battle',
      state: 'get_dungeon_battle_state',
      objective_start: 'start_dungeon_objective',
      quit: 'quit_dungeon_battle',
      join: 'join_dungeon_battle'
    }
    rpc = { name: names[action], args: { p_user_id: user.id, p_battle_id: body.battle_id } }

  } else if (action === 'ping') {
    // Advisory only — it drives the "who is falling behind" indicator and
    // never a reward, which is why an unverifiable number is safe here.
    if (!isUuid(body.battle_id)) return json({ success: false, error: 'A valid battle_id is required.' }, 400)
    const progress = Number(body.progress)
    if (!Number.isFinite(progress) || progress < 0 || progress > MAX_ACHIEVED) {
      return json({ success: false, error: `progress must be between 0 and ${MAX_ACHIEVED}.` }, 400)
    }
    rpc = {
      name: 'ping_dungeon_progress',
      args: { p_user_id: user.id, p_battle_id: body.battle_id, p_progress: progress }
    }

  } else if (action === 'submit') {
    if (!isUuid(body.battle_id)) return json({ success: false, error: 'A valid battle_id is required.' }, 400)

    const achieved = Number(body.achieved)
    if (!Number.isFinite(achieved) || achieved <= 0 || achieved > MAX_ACHIEVED) {
      return json({ success: false, error: `achieved must be between 0 and ${MAX_ACHIEVED}.` }, 400)
    }

    const source = typeof body.workout_source === 'string' ? body.workout_source : 'camera'
    if (!ALLOWED_SOURCES.includes(source)) {
      return json({ success: false, error: `workout_source must be one of: ${ALLOWED_SOURCES.join(', ')}.` }, 400)
    }

    const qualityProvided = body.form_quality !== undefined && body.form_quality !== null
    const quality = qualityProvided ? Number(body.form_quality) : null
    if (qualityProvided && (!Number.isFinite(quality!) || quality! < 0 || quality! > 1)) {
      return json({ success: false, error: 'form_quality must be between 0 and 1.' }, 400)
    }

    const weightProvided = body.weight_kg !== undefined && body.weight_kg !== null && body.weight_kg !== ''
    const weightKg = weightProvided ? Number(body.weight_kg) : null
    if (weightProvided && (!Number.isFinite(weightKg!) || weightKg! < 0 || weightKg! > MAX_WEIGHT_KG)) {
      return json({ success: false, error: `weight_kg must be between 0 and ${MAX_WEIGHT_KG}.` }, 400)
    }

    // Present only for an assist: the teammate's objective this set counts
    // toward. The server checks it belongs to this battle and is open.
    const assignmentId = body.assignment_id ?? null
    if (assignmentId !== null && !isUuid(assignmentId)) {
      return json({ success: false, error: 'assignment_id must be a UUID.' }, 400)
    }

    rpc = {
      name: 'submit_dungeon_objective',
      args: {
        p_user_id: user.id,
        p_battle_id: body.battle_id,
        p_achieved: achieved,
        p_form_quality: quality,
        p_workout_source: source,
        p_weight_kg: weightKg,
        p_assignment_id: assignmentId
      }
    }

  } else {
    return json({
      success: false,
      error: 'action must be one of: create, parties, join, start, state, objective_start, submit, ping, quit.'
    }, 400)
  }

  const { data, error } = await admin.rpc(rpc.name, rpc.args)
  if (error) return json({ success: false, error: playerMessage(error.message) }, 400)

  return json(data, 200)
})
