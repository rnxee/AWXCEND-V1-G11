import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { hasPermission, ROLES } from '../_shared/permissions.ts'
import { recordAdminAction } from '../_shared/audit.ts'

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

  const admin = getAdminClient()

  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profileError || !hasPermission(profile?.role, 'manage_roles')) {
    return new Response(JSON.stringify({ success: false, error: 'Admin access required' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const body = await req.json().catch(() => ({}))
  const targetUserId = typeof body.user_id === 'string' ? body.user_id.trim() : ''
  const newRole = typeof body.role === 'string' ? body.role.trim().toLowerCase() : ''

  const errors: string[] = []
  if (!targetUserId) errors.push('user_id is required')
  if (!ROLES.includes(newRole as typeof ROLES[number])) errors.push(`role must be one of: ${ROLES.join(', ')}`)
  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Blocks self-demotion — an admin changing their own role here could lock
  // themselves out of this exact screen with no recovery path short of
  // direct DB access. Role changes to your own account have to come from a
  // different admin (or the DB directly), same reasoning as not letting a
  // moderator unilaterally promote themselves.
  if (targetUserId === user.id) {
    return new Response(JSON.stringify({ success: false, error: 'You cannot change your own role' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { data: before } = await admin.from('users').select('role').eq('id', targetUserId).maybeSingle()

  const { data: updated, error } = await admin
    .from('users')
    .update({ role: newRole })
    .eq('id', targetUserId)
    .select('id, username, role')
    .single()

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  if (!updated) {
    return new Response(JSON.stringify({ success: false, error: 'User not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const auditRecorded = await recordAdminAction(admin, {
    actorUserId: user.id,
    action: 'user.role_change',
    targetType: 'user',
    targetId: targetUserId,
    metadata: { previous_role: before?.role ?? null, new_role: newRole }
  })

  return new Response(JSON.stringify({ success: true, user: updated, audit_recorded: auditRecorded }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
