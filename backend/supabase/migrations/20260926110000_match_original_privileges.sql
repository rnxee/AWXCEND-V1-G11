-- Security fix for the baseline clone: restore the original project's privileges.
--
-- A new Supabase project's default privileges grant EXECUTE on every new function (and ALL on
-- every new table/view) to anon and authenticated. The original project's migrations revoked
-- those grants one by one; a schema dump does not carry the revokes, so after the baseline every
-- public function - including 87 SECURITY DEFINER ones that take a p_user_id - was callable by
-- anyone through /rest/v1/rpc. The app only reaches these through Edge Functions (service role).
--
-- Rule for future migrations (same as the original project): after creating a function, add
--   REVOKE EXECUTE ON FUNCTION public.<name>(<args>) FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  fn regprocedure;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')  -- skip extension-owned
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
  END LOOP;
END $$;

-- Tables and views the original project keeps closed to anon/authenticated (service role only).
-- strength_prs is a view: views bypass RLS, so this revoke is what keeps it private.
REVOKE ALL ON TABLE
  public.admin_audit_log, public.commodity_reference_prices, public.exercise_library,
  public.market_commodities, public.privacy_export_coverage, public.privacy_notices,
  public.strength_prs, public.training_limits, public.training_plan_days,
  public.training_plan_feedback, public.training_plans, public.training_surveys,
  public.user_budget_settings, public.user_commodity_prices, public.user_consents,
  public.verification_applications
FROM anon, authenticated;
