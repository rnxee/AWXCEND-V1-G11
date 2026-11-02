CREATE TABLE IF NOT EXISTS public.user_report_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_report_id uuid NOT NULL REFERENCES public.user_reports(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  original_name text NOT NULL CHECK (char_length(original_name) BETWEEN 1 AND 255),
  storage_path text NOT NULL UNIQUE,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes integer NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_report_attachments_report_idx
  ON public.user_report_attachments (user_report_id, created_at);

ALTER TABLE public.user_report_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_report_attachments FROM anon, authenticated;
GRANT ALL ON public.user_report_attachments TO service_role;
