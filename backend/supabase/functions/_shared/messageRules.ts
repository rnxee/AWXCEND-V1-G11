import { cleanText, MAX_CHAT_WORDS, wordCount } from './validation.ts'

// Chat and DM messages: the same text rules for sending and for editing, and how long an edit stays possible.
export const EDIT_WINDOW_MINUTES = 15

/** The cleaned text, or an error for the player. */
export function checkMessage(raw: unknown, maxLength: number): { text: string; error: string | null } {
  const text = cleanText(raw)
  if (!text) return { text, error: 'message is required' }
  if (text.length > maxLength) return { text, error: `message must be ${maxLength} characters or fewer` }
  if (wordCount(text) > MAX_CHAT_WORDS) return { text, error: `message must be ${MAX_CHAT_WORDS} words or fewer` }
  return { text, error: null }
}

/** chat_messages.created_at has no zone (it is UTC); direct_messages.created_at has one. */
function parseUtc(iso: string): number {
  return Date.parse(/(Z|[+-]\d\d(:?\d\d)?)$/.test(iso) ? iso : `${iso}Z`)
}

export function canEdit(createdAt: string, now = Date.now()): boolean {
  const t = parseUtc(createdAt)
  return Number.isFinite(t) && now - t < EDIT_WINDOW_MINUTES * 60_000
}
