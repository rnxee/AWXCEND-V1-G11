// Verification rules. Pure — tested directly (src/lib/verificationRules.test.js).
//
// Two unrelated statuses live here, and neither touches form_verified:
//   * Consistent training history: an ACTIVITY signal from workouts logged in
//     GymApp. It is not evidence of lifting experience.
//   * Verified coach: admin review of submitted evidence. A file hash kept
//     after deletion shows which file was reviewed, not that it is genuine.

export const TRAINING_HISTORY_REQUIRED_WEEKS = 26
export const TRAINING_HISTORY_REQUIRED_SPAN_DAYS = 182 // about 6 months

export const EVIDENCE_BUCKET = 'verification-evidence'
export const MAX_EVIDENCE_FILES = 3
export const MAX_EVIDENCE_BYTES = 2 * 1024 * 1024
export const SUMMARY_MIN_CHARS = 50
export const SUMMARY_MAX_CHARS = 2000
export const EVIDENCE_LINK_SECONDS = 300

export type TrainingCounts = { active_weeks: number | null; first_logged_at: string | null; last_logged_at: string | null }

/** Active weeks and the span of logged activity, and whether both thresholds are met. */
export function trainingHistoryStatus(counts: TrainingCounts | null) {
  const activeWeeks = Number(counts?.active_weeks ?? 0)
  let spanDays = 0
  if (counts?.first_logged_at && counts?.last_logged_at) {
    const ms = Date.parse(counts.last_logged_at) - Date.parse(counts.first_logged_at)
    spanDays = Number.isFinite(ms) && ms > 0 ? Math.floor(ms / 86400000) : 0
  }
  return {
    active_weeks: activeWeeks,
    required_weeks: TRAINING_HISTORY_REQUIRED_WEEKS,
    span_days: spanDays,
    required_span_days: TRAINING_HISTORY_REQUIRED_SPAN_DAYS,
    qualifies: activeWeeks >= TRAINING_HISTORY_REQUIRED_WEEKS && spanDays >= TRAINING_HISTORY_REQUIRED_SPAN_DAYS
  }
}

export function evidencePath(userId: string, applicationId: string, index: number): string {
  return `${userId}/${applicationId}/${index + 1}.jpg`
}

/**
 * Decodes one evidence image. Accepts only base64 of a complete JPEG (the
 * client re-encodes every image to JPEG, which also drops EXIF location data),
 * up to MAX_EVIDENCE_BYTES.
 */
export function decodeJpegBase64(raw: unknown): { bytes: Uint8Array | null; error: string | null } {
  if (typeof raw !== 'string' || raw.length === 0) return { bytes: null, error: 'Each image must be sent as base64 text.' }
  if (raw.length > Math.ceil(MAX_EVIDENCE_BYTES / 3) * 4 + 4) return { bytes: null, error: 'Each image must be 2 MB or smaller.' }
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) return { bytes: null, error: 'An image was not valid base64.' }
  let bytes: Uint8Array
  try {
    const binary = atob(raw)
    bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  } catch {
    return { bytes: null, error: 'An image was not valid base64.' }
  }
  if (bytes.length > MAX_EVIDENCE_BYTES) return { bytes: null, error: 'Each image must be 2 MB or smaller.' }
  const isJpeg = bytes.length > 4 &&
    bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff &&
    bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9
  if (!isJpeg) return { bytes: null, error: 'Images must be JPEG (the app converts photos automatically).' }
  return { bytes, error: null }
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

export function validateSummary(raw: unknown): { summary: string | null; error: string | null } {
  const summary = typeof raw === 'string' ? raw.trim() : ''
  if (summary.length < SUMMARY_MIN_CHARS || summary.length > SUMMARY_MAX_CHARS) {
    return { summary: null, error: `Describe your coaching experience in ${SUMMARY_MIN_CHARS} to ${SUMMARY_MAX_CHARS} characters.` }
  }
  return { summary, error: null }
}
