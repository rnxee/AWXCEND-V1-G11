CREATE TABLE IF NOT EXISTS public.gymmunity_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.gymmunity_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  parent_comment_id uuid REFERENCES public.gymmunity_comments(id) ON DELETE SET NULL,
  content text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz
);

CREATE INDEX IF NOT EXISTS gymmunity_comments_post_idx
  ON public.gymmunity_comments (post_id, created_at);
CREATE INDEX IF NOT EXISTS gymmunity_comments_parent_idx
  ON public.gymmunity_comments (parent_comment_id, created_at);

ALTER TABLE public.gymmunity_comments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gymmunity_comments FROM anon, authenticated;
GRANT ALL ON public.gymmunity_comments TO service_role;
