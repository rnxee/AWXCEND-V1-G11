// Central RBAC definition — every role-gated Edge Function should check
// permissions through hasPermission() instead of hardcoding `role === 'admin'`.
// Adding a role or a permission is a one-file change here; nothing else
// needs touching except the functions that actually gate on the new
// permission. Roles are on `public.users.role` (CHECK-constrained), not a
// separate roles table — this app doesn't need per-user multi-role
// assignment or admin-configurable roles yet, so a static map is the
// simplest thing that's still genuinely permission-based rather than
// scattering `role === 'admin'` checks across every function.
export const ROLES = ['user', 'moderator', 'admin'] as const
export type Role = typeof ROLES[number]

export const PERMISSIONS = {
  // Approve/reject pending Gymmunity posts
  moderate_posts: ['moderator', 'admin'],
  // Review/dismiss user-submitted reports about other users
  moderate_users: ['moderator', 'admin'],
  // Review/resolve user-submitted bug/feature reports about the app itself
  manage_bug_reports: ['moderator', 'admin'],
  // Change another user's role
  manage_roles: ['admin'],
  // Create, open, configure and cancel Dungeon events. Admin-only: a Dungeon
  // hands out exclusive rewards and sets its own difficulty, so opening one
  // is an economy decision rather than a moderation one.
  manage_dungeons: ['admin'],
  // Read the append-only admin audit log
  view_audit_log: ['admin'],
  // Review coach verification applications and their evidence. Admin-only
  // while moderator access scope is pending privacy review.
  review_verifications: ['admin'],
  // Add, correct and hide foods in the food database. Admin-only: the values
  // feed every meal log's nutrition and must cite where they come from.
  manage_foods: ['admin']
} as const

export type Permission = keyof typeof PERMISSIONS

export function hasPermission(role: string | null | undefined, permission: Permission): boolean {
  return (PERMISSIONS[permission] as readonly string[]).includes(role ?? '')
}
