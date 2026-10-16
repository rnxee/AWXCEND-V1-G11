import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { hasPermission } from '../_shared/permissions.ts'
import { recordAdminAction } from '../_shared/audit.ts'
import { isUuid } from '../_shared/validation.ts'
import { canLift, canSanction, computeEndsAt, isPrivilege, sanctionMessage } from '../_shared/sanctions.ts'

// Moderators and admins ban an account or restrict some of its privileges.
//
//   GET  ?view=active                  sanctions in force now (default)
//   GET  ?view=history&user_id=<uuid>  one player's sanctions, lifted and expired included
//   GET  ?query=<username>             players to sanction, with their role
//   POST { action: 'issue', user_id, kind: 'ban'|'restrict', privileges?, reason, report_id?,
//          permanent? | until? | amount + unit }
//   POST { action: 'lift', sanction_id, note? }
//
// A ban is enforced twice: getVerifiedUser refuses every function call at once, and Supabase
// Auth's ban_duration stops sign-in and token refresh. Every decision is audited.

const RL_MAX = 60
const RL_WINDOW_SECONDS = 3600
const PERMANENT = '876000h' // 100 years: Supabase Auth has no "forever"

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

// deno-lint-ignore no-explicit-any
async function syncAuthBan(admin: any, userId: string) {
  // The Auth ban follows the longest open ban, so lifting one of two bans keeps the other.
  const { data } = await admin.from('user_sanctions').select('ends_at')
    .eq('user_id', userId).eq('kind', 'ban').is('lifted_at', null)
    .or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`)
  const rows = data ?? []
  let duration = 'none'
  if (rows.some((r: { ends_at: string | null }) => r.ends_at === null)) duration = PERMANENT
  else if (rows.length > 0) {
    const last = Math.max(...rows.map((r: { ends_at: string }) => Date.parse(r.ends_at)))
    duration = `${Math.max(1, Math.ceil((last - Date.now()) / 3600_000))}h`
  }
  const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: duration })
  if (error) console.error('[sanctions] auth ban sync failed:', error.message)
  return !error
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const { user, error: authError } = await getVerifiedUser(req)
  if (!user) return json({ success: false, error: authError }, 401)

  const admin = getAdminClient()
  const { data: me } = await admin.from('users').select('id, role').eq('id', user.id).maybeSingle()
  if (!me || !hasPermission(me.role, 'sanction_users')) {
    return json({ success: false, error: 'Moderator access required' }, 403)
  }
  if (!(await checkRateLimit(user.id, 'sanctions', RL_MAX, RL_WINDOW_SECONDS))) return rateLimitResponse(corsHeaders)

  if (req.method === 'GET') {
    const params = new URL(req.url).searchParams
    const query = (params.get('query') ?? '').trim()
    if (query) {
      const literal = query.slice(0, 30).replace(/[\\%_]/g, (c) => `\\${c}`)  // "_" is a common username letter
      const { data, error } = await admin.from('users').select('id, username, role, rank')
        .ilike('username', `%${literal}%`).neq('id', user.id).limit(20)
      if (error) return json({ success: false, error: 'Could not search players.' }, 500)
      return json({ success: true, users: data ?? [] })
    }
    const view = params.get('view') ?? 'active'
    let q = admin.from('user_sanctions')
      .select('id, user_id, kind, privileges, reason, report_id, ends_at, issued_by_role, created_at, lifted_at, lift_reason, ' +
        'player:user_id ( username, role ), issuer:issued_by ( username ), lifter:lifted_by ( username )')
      .order('created_at', { ascending: false }).limit(100)
    if (view === 'history') {
      const target = params.get('user_id')
      if (!isUuid(target)) return json({ success: false, error: 'A valid user_id is required.' }, 400)
      q = q.eq('user_id', target)
    } else {
      q = q.is('lifted_at', null).or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`)
    }
    const { data, error } = await q
    if (error) return json({ success: false, error: 'Could not load sanctions.' }, 500)
    // deno-lint-ignore no-explicit-any
    const sanctions = (data ?? []).map((s: any) => ({ ...s, message: sanctionMessage(s) }))
    return json({ success: true, sanctions })
  }

  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)
  const body = await req.json().catch(() => ({}))

  if (body.action === 'issue') {
    const errors: string[] = []
    if (!isUuid(body.user_id)) errors.push('A valid user_id is required.')
    if (!['ban', 'restrict'].includes(body.kind)) errors.push('kind must be ban or restrict.')
    const privileges: string[] = Array.isArray(body.privileges) ? [...new Set(body.privileges as unknown[])].filter(isPrivilege) : []
    if (body.kind === 'restrict' && privileges.length === 0) errors.push('Pick at least one privilege to restrict.')
    const reason = typeof body.reason === 'string' ? body.reason.trim() : ''
    if (!reason || reason.length > 500) errors.push('A reason of 1-500 characters is required (the player reads it).')
    if (body.report_id !== undefined && body.report_id !== null && !isUuid(body.report_id)) errors.push('report_id must be a valid id.')
    const end = computeEndsAt(body)
    if (!end.ok) errors.push(end.error)
    if (errors.length) return json({ success: false, errors }, 400)

    const { data: target } = await admin.from('users').select('id, username, role').eq('id', body.user_id).maybeSingle()
    if (!target) return json({ success: false, error: 'Player not found.' }, 404)
    const refusal = canSanction(me, target)
    if (refusal) return json({ success: false, error: refusal }, 403)
    if (body.report_id) {  // a sanction can only settle a report about this same player
      const { data: report } = await admin.from('user_reports').select('reported_user_id').eq('id', body.report_id).maybeSingle()
      if (!report || report.reported_user_id !== target.id) {
        return json({ success: false, error: 'That report is not about this player.' }, 400)
      }
    }

    const endsAt = end.ok ? end.endsAt : null
    const { data: row, error } = await admin.from('user_sanctions').insert({
      user_id: target.id, kind: body.kind, privileges: body.kind === 'ban' ? [] : privileges, reason,
      report_id: body.report_id ?? null, ends_at: endsAt ? endsAt.toISOString() : null,
      issued_by: user.id, issued_by_role: me.role
    }).select().single()
    if (error) return json({ success: false, error: `Could not save the sanction: ${error.message}` }, 400)

    const authSynced = body.kind === 'ban' ? await syncAuthBan(admin, target.id) : true
    if (body.report_id) {  // acting on a report closes it
      await admin.from('user_reports').update({ status: 'reviewed', reviewed_by: user.id, reviewed_at: new Date().toISOString() })
        .eq('id', body.report_id).eq('status', 'pending')
    }
    const audited = await recordAdminAction(admin, {
      actorUserId: user.id, action: 'sanction.issue', targetType: 'user', targetId: target.id,
      metadata: { sanction_id: row.id, kind: row.kind, privileges: row.privileges, ends_at: row.ends_at, report_id: row.report_id }
    })
    return json({ success: true, sanction: { ...row, message: sanctionMessage(row) }, auth_synced: authSynced, audit_recorded: audited })
  }

  if (body.action === 'lift') {
    if (!isUuid(body.sanction_id)) return json({ success: false, error: 'A valid sanction_id is required.' }, 400)
    const note = typeof body.note === 'string' ? body.note.trim().slice(0, 500) : ''
    const { data: s } = await admin.from('user_sanctions').select('id, user_id, kind, issued_by_role, lifted_at')
      .eq('id', body.sanction_id).maybeSingle()
    if (!s) return json({ success: false, error: 'Sanction not found.' }, 404)
    if (s.lifted_at) return json({ success: false, error: 'That sanction was already lifted.' }, 409)
    if (s.user_id === user.id) return json({ success: false, error: "You can't lift your own sanction." }, 403)
    const refusal = canLift(me.role, s.issued_by_role)
    if (refusal) return json({ success: false, error: refusal }, 403)

    // lifted_at IS NULL in the update itself: of two moderators lifting at once, only one counts.
    const { data: lifted, error } = await admin.from('user_sanctions')
      .update({ lifted_at: new Date().toISOString(), lifted_by: user.id, lift_reason: note || null })
      .eq('id', s.id).is('lifted_at', null).select('id')
    if (error) return json({ success: false, error: 'Could not lift the sanction.' }, 500)
    if (!lifted || lifted.length === 0) return json({ success: false, error: 'That sanction was already lifted.' }, 409)
    const authSynced = s.kind === 'ban' ? await syncAuthBan(admin, s.user_id) : true
    const audited = await recordAdminAction(admin, {
      actorUserId: user.id, action: 'sanction.lift', targetType: 'user', targetId: s.user_id,
      metadata: { sanction_id: s.id, kind: s.kind, note: note || null }
    })
    return json({ success: true, auth_synced: authSynced, audit_recorded: audited })
  }

  return json({ success: false, error: 'action must be issue or lift.' }, 400)
})
