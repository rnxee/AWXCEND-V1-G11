import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

// Returns ALL of the caller's saved reference reps in one request, rather than
// one per exercise. CameraWorkout lets the user switch exercises freely from a
// 16-item picker, so a per-exercise fetch would mean a round trip on every tap;
// the whole set is a few hundred KB at most and is fetched once when the screen
// opens.

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
    .from('user_exercise_templates')
    .select('exercise, frames, dimensions, frame_count, updated_at')
    .eq('user_id', user.id)

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // Keyed by exercise so the client can look one up directly instead of
  // scanning an array on every exercise switch.
  const templates: Record<string, unknown> = {}
  for (const row of data ?? []) {
    templates[row.exercise] = {
      frames: row.frames,
      dimensions: row.dimensions,
      frameCount: row.frame_count,
      updatedAt: row.updated_at
    }
  }

  return new Response(JSON.stringify({ success: true, templates }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
