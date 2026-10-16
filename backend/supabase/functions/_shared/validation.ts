// Small shared validators. Kept dependency-free so any function can import
// one line without pulling in anything else.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * True only for a canonical UUID string. Several functions interpolate a
 * request-supplied id straight into a PostgREST `.or(...)` filter; supabase-js
 * escapes those values so the pattern isn't currently exploitable, but
 * validating the shape up front removes the whole class of risk (and rejects
 * malformed ids with a clean 400 instead of a confusing empty result).
 */
export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v)
}

// Characters that break chat layouts or hide text: control codes (newline and tab stay),
// zero-width spaces, bidi overrides that flip text direction, and the byte-order mark.
// U+200D (zero-width joiner) stays: family and other combined emoji are built with it.
const BAD_CHARS_RE = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F\u200B\u200C\u200E\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/g

/** Trimmed, NFC-normalised text without invisible/direction characters, and with "zalgo" stacks of
 *  combining marks cut to two (enough for any real language and keycap emoji). Non-strings become ''. */
export function cleanText(v: unknown): string {
  if (typeof v !== 'string') return ''
  return v.normalize('NFC').replace(BAD_CHARS_RE, '').replace(/(\p{M}{2})\p{M}+/gu, '$1').trim()
}

export const MAX_CHAT_WORDS = 100

export function wordCount(s: string): number {
  return s.split(/\s+/).filter(Boolean).length
}

// Terms of Use section 1: AWXCEND is for adults only (age of majority in the Philippines).
export const MIN_AGE = 18
