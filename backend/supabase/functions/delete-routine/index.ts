import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { isUuid } from '../_shared/validation.ts'

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

  if (!(await checkRateLimit(user.id, 'delete_routine', 30, 600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const routineId = typeof body.routine_id === 'string' ? body.routine_id : ''

  if (!isUuid(routineId)) {
    return new Response(JSON.stringify({ success: false, errors: ['routine_id must be a valid uuid'] }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // The user_id filter is what makes this safe: the admin client bypasses RLS,
  // so scoping the delete to the caller is the only thing stopping one user
  // from deleting another's routine by guessing an id. routine_exercises rows
  // go with it via ON DELETE CASCADE.
  const { data, error } = await admin
    .from('routines')
    .delete()
    .eq('id', routineId)
    .eq('user_id', user.id)
    .select('id')

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  if (!data || data.length === 0) {
    return new Response(JSON.stringify({ success: false, error: 'Routine not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
