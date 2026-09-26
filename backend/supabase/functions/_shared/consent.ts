import { getAdminClient } from './supabaseAdmin.ts'

// Server-side consent checks for features that send or store data covered by
// a notice (camera reference reps, AI features). The record lives in
// public.user_consents and is checked here, so skipping the notice in the
// client doesn't skip it on the server.

export type ConsentType = 'privacy_notice' | 'camera' | 'gps' | 'ai_features' | 'relative_leaderboard'

/**
 * Null when the user has acknowledged the CURRENT version of the notice;
 * otherwise a 403 the client recognises by `code: 'CONSENT_REQUIRED'`.
 * Fails closed: if the check itself errors, the request is refused.
 */
export async function consentRequiredResponse(
  userId: string,
  consentType: ConsentType,
  corsHeaders: Record<string, string>
): Promise<Response | null> {
  const { data, error } = await getAdminClient().rpc('has_current_consent', {
    p_user_id: userId,
    p_consent_type: consentType
  })
  if (!error && data === true) return null
  if (error) console.error(`[consent] check failed for ${consentType}:`, error.message)
  return new Response(JSON.stringify({
    success: false,
    code: 'CONSENT_REQUIRED',
    consent_type: consentType,
    error: 'Please read and acknowledge the notice for this feature first.'
  }), {
    status: 403,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}
