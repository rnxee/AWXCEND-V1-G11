// Pure helpers for Supabase Storage URLs (tested in src/lib/storagePaths.test.js).

/**
 * The object path inside `bucket` for a public URL this project generated
 * (".../storage/v1/object/public/<bucket>/<path>"), or null for anything else —
 * so a URL pointing somewhere unexpected is never turned into a delete.
 */
export function storagePathFromPublicUrl(url: unknown, bucket: string): string | null {
  if (typeof url !== 'string' || !url) return null
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return null
  }
  const prefix = `/storage/v1/object/public/${bucket}/`
  if (!parsed.pathname.startsWith(prefix)) return null
  const path = decodeURIComponent(parsed.pathname.slice(prefix.length))
  // Uploads are "<user uuid>/<uuid>.jpg"; refuse traversal or anything odd.
  if (!/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg$/i.test(path)) return null
  return path
}
