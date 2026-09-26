import { EVIDENCE_BUCKET, evidencePath } from './verificationRules.ts'

// Deletes an application's evidence files from the private bucket and, only if
// that succeeded, records the deletion time on the application. Returns
// whether the files are gone. A failure leaves files_deleted_at empty so the
// admin screen can retry.
// deno-lint-ignore no-explicit-any
export async function deleteEvidenceFiles(admin: any, app: { application_id: string; user_id: string; evidence_count: number }): Promise<boolean> {
  const paths = Array.from({ length: app.evidence_count }, (_, i) => evidencePath(app.user_id, app.application_id, i))
  const { error } = await admin.storage.from(EVIDENCE_BUCKET).remove(paths)
  if (error) {
    console.error('[verification] evidence removal failed:', error.message)
    return false
  }
  const { error: markError } = await admin.rpc('mark_verification_files_deleted', { p_application_id: app.application_id })
  if (markError) console.error('[verification] could not record file deletion:', markError.message)
  return !markError
}
