-- Offline uploads need a durable, account-scoped idempotency boundary.  The
-- wrappers below execute the existing reward-producing functions in the same
-- transaction as the request record.  A retry after a lost HTTP response then
-- returns the original JSON instead of creating a second log or reward.

CREATE TABLE IF NOT EXISTS public.offline_sync_operations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id text NOT NULL,
  operation text NOT NULL CHECK (operation IN ('workout', 'meal')),
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, request_id)
);

ALTER TABLE public.offline_sync_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.offline_sync_operations FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.offline_sync_operations TO service_role;

CREATE OR REPLACE FUNCTION public.offline_log_workout(
  p_user_id uuid,
  p_request_id text,
  p_exercise text,
  p_sets integer,
  p_reps integer,
  p_rep_quality_score numeric,
  p_workout_source text,
  p_weight_kg numeric DEFAULT NULL,
  p_duration_seconds integer DEFAULT NULL,
  p_distance_m numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  v_response jsonb;
BEGIN
  IF p_request_id IS NULL OR p_request_id !~ '^[0-9a-fA-F-]{16,80}$' THEN
    RAISE EXCEPTION 'INVALID_REQUEST_ID: a stable client request id is required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_request_id, 0));
  SELECT response INTO v_response
    FROM public.offline_sync_operations
   WHERE user_id = p_user_id AND request_id = p_request_id
   FOR UPDATE;
  IF FOUND THEN RETURN v_response; END IF;

  v_response := public.log_workout_and_progress(
    p_user_id, p_exercise, p_sets, p_reps, p_rep_quality_score,
    p_workout_source, p_weight_kg, p_duration_seconds, p_distance_m
  );
  INSERT INTO public.offline_sync_operations (user_id, request_id, operation, response)
  VALUES (p_user_id, p_request_id, 'workout', v_response);
  RETURN v_response;
END;
$$;

CREATE OR REPLACE FUNCTION public.offline_log_meal(
  p_user_id uuid,
  p_request_id text,
  p_logged_method text,
  p_food_name text,
  p_weight_g numeric,
  p_calories numeric,
  p_protein numeric,
  p_carbs numeric,
  p_fat numeric,
  p_fiber numeric,
  p_sugar numeric,
  p_meal_period text,
  p_food_id uuid DEFAULT NULL,
  p_serving_label text DEFAULT NULL,
  p_usda jsonb DEFAULT NULL,
  p_usda_fdc_claimed integer DEFAULT NULL,
  p_gold_idempotency_key text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  v_response jsonb;
  v_log jsonb;
  v_gold jsonb;
BEGIN
  IF p_request_id IS NULL OR p_request_id !~ '^[0-9a-fA-F-]{16,80}$' THEN
    RAISE EXCEPTION 'INVALID_REQUEST_ID: a stable client request id is required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_request_id, 0));
  SELECT response INTO v_response
    FROM public.offline_sync_operations
   WHERE user_id = p_user_id AND request_id = p_request_id
   FOR UPDATE;
  IF FOUND THEN RETURN v_response; END IF;

  v_log := public.log_meal_entry(
    p_user_id, p_logged_method, p_food_name, p_weight_g, p_calories,
    p_protein, p_carbs, p_fat, p_fiber, p_sugar, p_meal_period,
    NULL, p_food_id, p_serving_label, p_usda, p_usda_fdc_claimed
  );
  v_gold := public.award_gold(
    p_user_id, 10, 'daily_meal_log', (v_log->>'id')::uuid, p_gold_idempotency_key
  );
  v_response := jsonb_build_object(
    'success', TRUE,
    'log', v_log,
    'gold_awarded', CASE WHEN COALESCE((v_gold->>'awarded')::boolean, FALSE) THEN 10 ELSE 0 END
  );
  INSERT INTO public.offline_sync_operations (user_id, request_id, operation, response)
  VALUES (p_user_id, p_request_id, 'meal', v_response);
  RETURN v_response;
END;
$$;

ALTER FUNCTION public.offline_log_workout(uuid, text, text, integer, integer, numeric, text, numeric, integer, numeric)
  OWNER TO postgres;
ALTER FUNCTION public.offline_log_meal(uuid, text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, uuid, text, jsonb, integer, text)
  OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.offline_log_workout(uuid, text, text, integer, integer, numeric, text, numeric, integer, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.offline_log_meal(uuid, text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, uuid, text, jsonb, integer, text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.offline_log_workout(uuid, text, text, integer, integer, numeric, text, numeric, integer, numeric) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.offline_log_meal(uuid, text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, uuid, text, jsonb, integer, text) FROM PUBLIC, anon, authenticated;
