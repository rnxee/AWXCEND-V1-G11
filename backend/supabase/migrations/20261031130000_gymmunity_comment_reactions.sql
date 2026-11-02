CREATE TABLE IF NOT EXISTS public.gymmunity_comment_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id uuid NOT NULL REFERENCES public.gymmunity_comments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reaction text NOT NULL CHECK (reaction IN ('like', 'love', 'fire', 'strong')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS gymmunity_comment_reactions_comment_idx
  ON public.gymmunity_comment_reactions (comment_id);

ALTER TABLE public.gymmunity_comment_reactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gymmunity_comment_reactions FROM anon, authenticated;
GRANT ALL ON public.gymmunity_comment_reactions TO service_role;
