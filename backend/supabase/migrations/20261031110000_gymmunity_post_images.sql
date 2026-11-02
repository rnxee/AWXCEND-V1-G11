-- A post keeps its original image_url for old clients and moderation data, but
-- new uploads live here so a post can have an ordered gallery.
CREATE TABLE IF NOT EXISTS public.gymmunity_post_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.gymmunity_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  storage_path text NOT NULL UNIQUE,
  sort_order integer NOT NULL CHECK (sort_order >= 0 AND sort_order < 10),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, sort_order)
);

CREATE INDEX IF NOT EXISTS gymmunity_post_images_post_idx
  ON public.gymmunity_post_images (post_id, sort_order);

ALTER TABLE public.gymmunity_post_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gymmunity_post_images FROM anon, authenticated;
GRANT ALL ON public.gymmunity_post_images TO service_role;
