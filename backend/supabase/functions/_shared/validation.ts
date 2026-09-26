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
