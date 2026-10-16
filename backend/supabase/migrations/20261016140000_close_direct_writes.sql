-- Security: routines, routine exercises and camera templates kept "own rows" write policies from the
-- original web app, so anyone signed in could write them straight through /rest/v1 with the public key,
-- skipping the Edge Functions' length limits, exercise checks and rate limits (unbounded rows and
-- jsonb = a cheap way to fill the database). Every app path writes them through save-routine,
-- delete-routine and save-exercise-template with the service role, so the direct grants go.
-- Reads stay as they were (own rows only, by RLS).
REVOKE INSERT, UPDATE, DELETE ON TABLE
  public.routines, public.routine_exercises, public.user_exercise_templates
FROM anon, authenticated;

-- Nothing outside the service role ever touches the rate-limit counters. RLS with no policy already
-- refuses them; this makes it explicit.
REVOKE ALL ON TABLE public.rate_limits FROM anon, authenticated;
