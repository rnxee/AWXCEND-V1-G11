// Moderation sanction rules: pure, no imports, so `node --test` can run them (sanctionRules.test.ts).
// The table lookups are in sanctions.ts.
//
// Who can sanction whom: moderators sanction players only; admins also sanction moderators;
// nobody sanctions an admin or themselves. A moderator can't lift an admin's sanction.

export const PRIVILEGES = ['post', 'chat', 'dm', 'friend_request', 'report'] as const
export type Privilege = typeof PRIVILEGES[number]

export const PRIVILEGE_LABELS: Record<Privilege, string> = {
  post: 'posting', chat: 'community chat', dm: 'direct messages', friend_request: 'friend requests', report: 'reporting'
}

export const UNITS = ['hours', 'days', 'weeks', 'months', 'years'] as const
export type Unit = typeof UNITS[number]
const MAX_YEARS = 100

export function isPrivilege(v: unknown): v is Privilege {
  return typeof v === 'string' && (PRIVILEGES as readonly string[]).includes(v)
}

/** When a sanction ends: `amount` `unit` from `now`, an exact `until`, or null for permanent.
 * Months and years land on the same day of the month, clamped to its last day (31 Jan + 1 month = 28/29 Feb). */
export function computeEndsAt(
  d: { permanent?: boolean; until?: string; amount?: number; unit?: string },
  now: Date = new Date()
): { ok: true; endsAt: Date | null } | { ok: false; error: string } {
  if (d.permanent === true) return { ok: true, endsAt: null }
  const cap = new Date(now)
  cap.setUTCFullYear(cap.getUTCFullYear() + MAX_YEARS)
  if (typeof d.until === 'string' && d.until) {
    const t = new Date(d.until)
    if (Number.isNaN(t.getTime())) return { ok: false, error: 'until is not a valid date.' }
    if (t <= now) return { ok: false, error: 'until must be in the future.' }
    return { ok: true, endsAt: t > cap ? cap : t }
  }
  const n = Number(d.amount)
  if (!Number.isInteger(n) || n < 1 || n > 1000) return { ok: false, error: 'amount must be a whole number from 1 to 1000.' }
  if (!(UNITS as readonly string[]).includes(d.unit ?? '')) return { ok: false, error: `unit must be one of: ${UNITS.join(', ')}.` }
  const end = new Date(now)
  if (d.unit === 'hours') end.setTime(end.getTime() + n * 3600_000)
  else if (d.unit === 'days') end.setTime(end.getTime() + n * 86400_000)
  else if (d.unit === 'weeks') end.setTime(end.getTime() + n * 7 * 86400_000)
  else {
    const months = d.unit === 'months' ? n : n * 12
    const day = end.getUTCDate()
    end.setUTCDate(1)
    end.setUTCMonth(end.getUTCMonth() + months)
    const last = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth() + 1, 0)).getUTCDate()
    end.setUTCDate(Math.min(day, last))
  }
  return { ok: true, endsAt: end > cap ? cap : end }
}

export function canSanction(actor: { id: string; role: string }, target: { id: string; role: string }): string | null {
  if (actor.id === target.id) return "You can't sanction yourself."
  if (target.role === 'admin') return "Admins can't be sanctioned."
  if (target.role === 'moderator' && actor.role !== 'admin') return 'Only an admin can sanction a moderator.'
  if (actor.role !== 'moderator' && actor.role !== 'admin') return 'Moderator access required.'
  return null
}

export function canLift(actorRole: string, issuedByRole: string): string | null {
  if (issuedByRole === 'admin' && actorRole !== 'admin') return "Only an admin can lift an admin's sanction."
  return null
}

/** Philippine time, like the rest of the game's calendar. */
function manila(d: Date): string {
  return new Intl.DateTimeFormat('en-PH', {
    timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
  }).format(d)
}

/** The exact text the player sees. A ban's text always starts with "Account suspended". */
export function sanctionMessage(s: { kind: string; privileges: string[]; reason: string; ends_at: string | null }): string {
  const until = s.ends_at ? `until ${manila(new Date(s.ends_at))}` : 'permanently'
  if (s.kind === 'ban') return `Account suspended ${until}. Reason: ${s.reason}`
  const what = s.privileges.map((p) => PRIVILEGE_LABELS[p as Privilege] ?? p).join(', ')
  return `You can't use ${what} ${until}. Reason: ${s.reason}`
}

