-- Evidence files belong to one report and one authenticated user.  The
-- service-role Edge Function is the only writer; RLS keeps the table private
-- if it is ever exposed through PostgREST later.
CREATE TABLE IF NOT EXISTS public.bug_report_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bug_report_id uuid NOT NULL REFERENCES public.bug_reports(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  original_name text NOT NULL CHECK (char_length(original_name) BETWEEN 1 AND 255),
  storage_path text NOT NULL UNIQUE,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes integer NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bug_report_attachments_report_idx
  ON public.bug_report_attachments (bug_report_id, created_at);

ALTER TABLE public.bug_report_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bug_report_attachments FROM anon, authenticated;
GRANT ALL ON public.bug_report_attachments TO service_role;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('bug-report-evidence', 'bug-report-evidence', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
