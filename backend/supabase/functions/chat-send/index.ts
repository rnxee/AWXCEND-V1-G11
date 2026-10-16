import { corsHeaders } from '../_shared/cors.ts'
import { getVerifiedUser } from '../_shared/auth.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rateLimit.ts'
import { getAdminClient } from '../_shared/supabaseAdmin.ts'
import { restrictionResponse } from '../_shared/sanctions.ts'
import { cleanText, MAX_CHAT_WORDS, wordCount } from '../_shared/validation.ts'

const MAX_MESSAGE_LENGTH = 500

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

  if (!(await checkRateLimit(user.id, 'chat_send', 30, 60))) {
    return rateLimitResponse(corsHeaders)
  }
  const restricted = await restrictionResponse(user.id, 'chat', corsHeaders)
  if (restricted) return restricted

  const body = await req.json().catch(() => ({}))
  const message = cleanText(body.message)

  const errors: string[] = []
  if (!message) errors.push('message is required')
  if (message.length > MAX_MESSAGE_LENGTH) errors.push(`message must be ${MAX_MESSAGE_LENGTH} characters or fewer`)
  if (wordCount(message) > MAX_CHAT_WORDS) errors.push(`message must be ${MAX_CHAT_WORDS} words or fewer`)

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const admin = getAdminClient()

  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('username, rank')
    .eq('id', user.id)
    .single()

  if (profileError || !profile) {
    return new Response(JSON.stringify({ success: false, error: profileError?.message ?? 'Profile not found' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  const { error } = await admin.from('chat_messages').insert({
    user_id: user.id,
    username: profile.username,
    rank_badge: profile.rank,
    message
  })

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
