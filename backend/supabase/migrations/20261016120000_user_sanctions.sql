-- Moderation sanctions: moderators and admins ban an account, or restrict some of its privileges,
-- for a set time or permanently. Same design as the web app's user_sanctions (2026-10-02), trimmed
-- to the privileges this app has.
--
-- A row is never deleted while the player exists; lifting (lifted_at/by/reason) is the undo, so
-- the history of who decided what stays. Service role only: players learn about their own
-- sanctions through the profile function and the ban message, never by reading this table.

CREATE TABLE IF NOT EXISTS public.user_sanctions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind            text NOT NULL CHECK (kind IN ('ban', 'restrict')),
  privileges      text[] NOT NULL DEFAULT '{}',
  reason          text NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 500),
  report_id       uuid REFERENCES public.user_reports(id) ON DELETE SET NULL,
  ends_at         timestamptz,                -- NULL = permanent
  issued_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  issued_by_role  text NOT NULL CHECK (issued_by_role IN ('moderator', 'admin')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  lifted_at       timestamptz,
  lifted_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  lift_reason     text CHECK (lift_reason IS NULL OR char_length(lift_reason) <= 500),
  CONSTRAINT user_sanctions_privileges_known
    CHECK (privileges <@ ARRAY['post', 'chat', 'dm', 'friend_request', 'report']::text[]),
  CONSTRAINT user_sanctions_restrict_needs_privileges
    CHECK (kind = 'ban' OR cardinality(privileges) > 0),
  CONSTRAINT user_sanctions_ends_after_start
    CHECK (ends_at IS NULL OR ends_at > created_at)
);

CREATE INDEX IF NOT EXISTS user_sanctions_open_idx
  ON public.user_sanctions (user_id) WHERE lifted_at IS NULL;
CREATE INDEX IF NOT EXISTS user_sanctions_created_idx
  ON public.user_sanctions (created_at DESC);

ALTER TABLE public.user_sanctions ENABLE ROW LEVEL SECURITY;  -- no policies: nobody but the service role
REVOKE ALL ON TABLE public.user_sanctions FROM anon, authenticated;
