// Chat history paging, plus two small helpers shared by the social endpoints.
//
// History is read newest-first, one page at a time: the first request gets the
// latest messages, and each "scroll up" asks for the page before the oldest
// one on screen (`before` = that message's created_at). Fetch limit + 1 rows
// so the extra one says whether older messages exist, without a count query.

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/

/** The `before` cursor, only if it is a real timestamp (it goes into a query). */
export function parseBefore(raw: string | null): string | null {
  if (!raw || !ISO_TIMESTAMP.test(raw) || Number.isNaN(Date.parse(raw))) return null
  return raw
}

/** Page size from the query string, clamped to 1..max. */
export function parseLimit(raw: string | null, fallback: number, max: number): number {
  const n = Number.parseInt(raw ?? '', 10)
  if (!Number.isFinite(n) || n < 1) return fallback
  return Math.min(n, max)
}

/** Newest-first rows (up to limit + 1) -> an oldest-first page and has_more. */
export function pageResult<T>(rowsNewestFirst: T[], limit: number): { items: T[]; has_more: boolean } {
  return {
    items: rowsNewestFirst.slice(0, limit).reverse(),
    has_more: rowsNewestFirst.length > limit
  }
}

/** Storage path of a Gymunnity post image from its public URL; null if foreign. */
export function postImagePath(url: string | null | undefined): string | null {
  if (!url) return null
  const marker = '/storage/v1/object/public/gymmunity-images/'
  const i = url.indexOf(marker)
  return i === -1 ? null : decodeURIComponent(url.slice(i + marker.length)) || null
}

/** A reported message's text, cut to what user_reports.context_excerpt holds. */
export function excerptOf(text: string): string {
  return text.slice(0, 500)
}
