import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { isUuid } from '../_shared/validation.ts'

// Creates or replaces one routine and its exercise list in a single call.
//
// Replace-whole-list rather than per-exercise CRUD: a routine is edited as one
// object in the UI (reorder, add, remove, then save), so diffing individual
// rows on the client would be work with no benefit. Position is assigned from
// array order here, which also means the client never has to manage position
// numbers or worry about gaps after a delete.

const MAX_NAME_LEN = 80
const MAX_NOTES_LEN = 500
const MAX_EXERCISES = 30
const MAX_SETS = 20
const MAX_REPS = 300
const MAX_DURATION = 21600 // 6h, same ceiling log-workout uses

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

  if (!(await checkRateLimit(user.id, 'save_routine', 30, 600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const routineId = typeof body.routine_id === 'string' && body.routine_id ? body.routine_id : null
  const name = typeof body.name === 'string' ? body.name.trim() : ''
  const notes = typeof body.notes === 'string' ? body.notes.trim() : null
  const exercises = Array.isArray(body.exercises) ? body.exercises : null

  const errors: string[] = []
  if (routineId !== null && !isUuid(routineId)) errors.push('routine_id must be a valid uuid')
  if (!name) errors.push('name is required')
  if (name.length > MAX_NAME_LEN) errors.push(`name must be ${MAX_NAME_LEN} characters or fewer`)
  if (notes && notes.length > MAX_NOTES_LEN) errors.push(`notes must be ${MAX_NOTES_LEN} characters or fewer`)
  if (!exercises || exercises.length === 0) errors.push('exercises must be a non-empty array')
  else if (exercises.length > MAX_EXERCISES) errors.push(`a routine may contain at most ${MAX_EXERCISES} exercises`)

  const cleaned: {
    exercise: string
    position: number
    target_sets: number | null
    target_reps: number | null
    target_duration_seconds: number | null
    notes: string | null
  }[] = []

  if (errors.length === 0) {
    for (let i = 0; i < exercises!.length; i++) {
      const e = exercises![i]
      const exercise = typeof e?.exercise === 'string' ? e.exercise.trim() : ''
      if (!exercise) { errors.push(`exercises[${i}].exercise is required`); break }

      const num = (v: unknown, max: number, label: string): number | null => {
        if (v === undefined || v === null || v === '') return null
        const n = Number(v)
        if (!Number.isInteger(n) || n < 1 || n > max) {
          errors.push(`exercises[${i}].${label} must be a whole number between 1 and ${max}`)
          return null
        }
        return n
      }

      cleaned.push({
        exercise,
        position: i,
        target_sets: num(e.target_sets, MAX_SETS, 'target_sets'),
        target_reps: num(e.target_reps, MAX_REPS, 'target_reps'),
        target_duration_seconds: num(e.target_duration_seconds, MAX_DURATION, 'target_duration_seconds'),
        notes: typeof e.notes === 'string' && e.notes.trim() ? e.notes.trim().slice(0, MAX_NOTES_LEN) : null
      })
      if (errors.length > 0) break
    }
  }

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  // Every named exercise must exist in the catalogue. Checked here rather than
  // relying on the foreign key alone so an unknown name comes back as a clear
  // message naming it, instead of an opaque constraint-violation string.
  const names = [...new Set(cleaned.map(c => c.exercise))]
  const { data: known, error: knownErr } = await admin
    .from('exercises').select('name').in('name', names)
  if (knownErr) {
    return new Response(JSON.stringify({ success: false, error: knownErr.message }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
  const knownSet = new Set((known ?? []).map(k => k.name))
  const unknown = names.filter(n => !knownSet.has(n))
  if (unknown.length > 0) {
    return new Response(JSON.stringify({
      success: false,
      errors: [`unknown exercise(s): ${unknown.join(', ')}`]
    }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }

  let id = routineId

  if (id) {
    // Ownership is re-checked explicitly. The admin client bypasses RLS, so
    // without this a caller could pass someone else's routine_id and overwrite
    // it — the policies on the table protect direct PostgREST access, not this
    // service-role path.
    const { data: owned } = await admin
      .from('routines').select('id').eq('id', id).eq('user_id', user.id).maybeSingle()
    if (!owned) {
      return new Response(JSON.stringify({ success: false, error: 'Routine not found' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    const { error } = await admin
      .from('routines')
      .update({ name, notes, updated_at: new Date().toISOString() })
      .eq('id', id)
    if (error) {
      return new Response(JSON.stringify({ success: false, error: error.message }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    // Children are replaced wholesale, matching the replace-whole-list contract.
    await admin.from('routine_exercises').delete().eq('routine_id', id)
  } else {
    const { data, error } = await admin
      .from('routines')
      .insert({ user_id: user.id, name, notes })
      .select('id')
      .single()
    if (error) {
      return new Response(JSON.stringify({ success: false, error: error.message }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    id = data.id
  }

  const { error: childErr } = await admin
    .from('routine_exercises')
    .insert(cleaned.map(c => ({ ...c, routine_id: id })))

  if (childErr) {
    return new Response(JSON.stringify({ success: false, error: childErr.message }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, routine_id: id, exercise_count: cleaned.length }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
