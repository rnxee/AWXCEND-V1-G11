import { getAdminClient } from './supabaseAdmin.ts'
import { sanctionMessage, type Privilege } from './sanctionRules.ts'

export * from './sanctionRules.ts'

// Moderation sanctions (table public.user_sanctions): lookups with the service role.
// The pure rules (who may sanction whom, end times, the player's message) are in sanctionRules.ts.

type OpenSanction = { id: string; kind: string; privileges: string[]; reason: string; ends_at: string | null }

/** Sanctions in force for a user right now. Fails OPEN (empty) on a lookup error, like the rate
 * limiter: a database hiccup must not lock every player out. */
export async function activeSanctions(userId: string): Promise<OpenSanction[]> {
  try {
    const { data, error } = await getAdminClient()
      .from('user_sanctions')
      .select('id, kind, privileges, reason, ends_at')
      .eq('user_id', userId)
      .is('lifted_at', null)
      .or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`)
    if (error) {
      console.error('[sanctions] lookup failed:', error.message)
      return []
    }
    return data ?? []
  } catch (e) {
    console.error('[sanctions] lookup threw:', (e as Error).message)
    return []
  }
}

/** The ban message if the user is banned now, else null. */
export async function banMessage(userId: string): Promise<string | null> {
  const ban = (await activeSanctions(userId)).find((s) => s.kind === 'ban')
  return ban ? sanctionMessage(ban) : null
}

/** A 403 for a restricted privilege, or null when the user may go ahead. */
export async function restrictionResponse(
  userId: string, privilege: Privilege, corsHeaders: Record<string, string>
): Promise<Response | null> {
  const hit = (await activeSanctions(userId)).find((s) => s.kind === 'restrict' && s.privileges.includes(privilege))
  if (!hit) return null
  return new Response(JSON.stringify({ success: false, code: 'RESTRICTED', error: sanctionMessage(hit) }), {
    status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}
