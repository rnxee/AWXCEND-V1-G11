// Writes one append-only admin_audit_log entry. Called AFTER an administrative
// action has succeeded. The entry can't be edited or deleted afterwards
// (trigger-enforced).
//
// Known limitation: the action and its audit entry are two separate database
// calls, so an audit write that fails leaves the action applied without an
// entry. It is logged, and the caller reports `audit_recorded: false` rather
// than hiding it.
// deno-lint-ignore no-explicit-any
export async function recordAdminAction(admin: any, entry: {
  actorUserId: string
  action: string
  targetType: string
  targetId: string | null
  metadata?: Record<string, unknown>
}): Promise<boolean> {
  const { error } = await admin.rpc('record_admin_action', {
    p_actor_user_id: entry.actorUserId,
    p_action: entry.action,
    p_target_type: entry.targetType,
    p_target_id: entry.targetId,
    p_metadata: entry.metadata ?? {}
  })
  if (error) {
    console.error(`[audit] failed to record ${entry.action}:`, error.message)
    return false
  }
  return true
}
