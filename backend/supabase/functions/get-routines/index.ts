import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

// Returns the caller's routines with their exercises nested and ordered.
// One request rather than a list call plus a detail call per routine — a user
// has a handful of routines, and the whole set is small enough that fetching
// it eagerly is cheaper than the round trips.

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

  const { data, error } = await admin
    .from('routines')
    .select(`
      id, name, notes, created_at, updated_at,
      routine_exercises (
        id, exercise, position, target_sets, target_reps, target_duration_seconds, notes
      )
    `)
    .eq('user_id', user.id)
    .order('updated_at', { ascending: false })

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // PostgREST doesn't guarantee ordering of an embedded resource, and position
  // is the whole point of a routine — sort here rather than hoping.
  const routines = (data ?? []).map(r => ({
    ...r,
    routine_exercises: [...(r.routine_exercises ?? [])].sort((a, b) => a.position - b.position)
  }))

  return new Response(JSON.stringify({ success: true, routines }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
