import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'

const ALLOWED_CATEGORIES = ['bug', 'feature_request', 'other']
const MAX_DESCRIPTION_LENGTH = 1000

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

  if (!(await checkRateLimit(user.id, 'report_bug', 10, 3600))) {
    return rateLimitResponse(corsHeaders)
  }

  const body = await req.json().catch(() => ({}))
  const category = typeof body.category === 'string' ? body.category.trim() : 'bug'
  const description = typeof body.description === 'string' ? body.description.trim() : ''

  const errors: string[] = []
  if (!ALLOWED_CATEGORIES.includes(category)) errors.push(`category must be one of: ${ALLOWED_CATEGORIES.join(', ')}`)
  if (!description) errors.push('description is required')
  if (description.length > MAX_DESCRIPTION_LENGTH) errors.push(`description must be at most ${MAX_DESCRIPTION_LENGTH} characters`)

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const { data: report, error: insertError } = await admin
    .from('bug_reports')
    .insert({
      user_id: user.id,
      category,
      description
    })
    .select()
    .single()

  if (insertError) {
    return new Response(JSON.stringify({ success: false, error: insertError.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true, report }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
