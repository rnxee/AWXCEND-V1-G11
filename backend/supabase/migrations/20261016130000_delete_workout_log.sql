-- Delete one of your own workouts and take back exactly what logging it gave.
--
-- log_workout_and_progress adds, in one transaction: the workout_logs row, its xp_earned to
-- users.xp and to the current path's user_specialization_xp (which sets rank), the same points
-- to the exercise's attribute, and (by trigger) a strength_records row. This undoes all of it in
-- one transaction with the user row locked, the same pattern as logging.
--
-- Deliberately narrow, so nothing that paid out elsewhere can be unwound:
--   * manual workouts only (camera sets may carry form credit),
--   * within 24 hours of logging,
--   * not a mission or dungeon set (it already dealt damage and may have paid a reward),
--   * not after a path change (its XP sits on the old path).
-- rank_history is a record of ranks reached, so it is left as it is.

CREATE OR REPLACE FUNCTION public.delete_workout_log(p_user_id uuid, p_log_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_focus_type  text;
  v_path_since  timestamptz;
  v_log         public.workout_logs%ROWTYPE;
  v_attribute   text;
  v_spec_xp     integer;
  v_rank        text;
  v_sub         integer;
BEGIN
  SELECT focus_type, specialization_started_at
    INTO v_focus_type, v_path_since
    FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: no user with id %', p_user_id USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_log FROM public.workout_logs WHERE id = p_log_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LOG_NOT_FOUND: That workout was not found.' USING ERRCODE = 'P0002';
  END IF;
  IF v_log.workout_source <> 'manual' THEN
    RAISE EXCEPTION 'NOT_DELETABLE: Only workouts you logged by hand can be deleted.' USING ERRCODE = 'P0001';
  END IF;
  -- workout_logs.logged_at is a naive timestamp holding UTC.
  IF v_log.logged_at < (now() AT TIME ZONE 'UTC') - interval '24 hours' THEN
    RAISE EXCEPTION 'NOT_DELETABLE: You can only delete a workout within 24 hours of logging it.' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.mission_objective_results WHERE workout_log_id = p_log_id)
     OR EXISTS (SELECT 1 FROM public.dungeon_objective_results WHERE workout_log_id = p_log_id) THEN
    RAISE EXCEPTION 'NOT_DELETABLE: This set counted toward a mission or dungeon, so it stays.' USING ERRCODE = 'P0001';
  END IF;
  IF v_path_since IS NOT NULL AND v_path_since > (v_log.logged_at AT TIME ZONE 'UTC') THEN
    RAISE EXCEPTION 'NOT_DELETABLE: You changed path after logging this, so its XP can''t be taken back.' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.strength_records WHERE workout_log_id = p_log_id;  -- the FK would only null it
  DELETE FROM public.workout_logs WHERE id = p_log_id;

  UPDATE public.users SET xp = GREATEST(COALESCE(xp, 0) - v_log.xp_earned, 0) WHERE id = p_user_id;
  UPDATE public.user_specialization_xp
     SET xp = GREATEST(xp - v_log.xp_earned, 0), updated_at = now()
   WHERE user_id = p_user_id AND focus_type = v_focus_type
  RETURNING xp INTO v_spec_xp;

  SELECT primary_attribute INTO v_attribute FROM public.exercises WHERE name = v_log.exercise;
  IF v_attribute IS NOT NULL THEN
    EXECUTE format('UPDATE public.users SET %I = GREATEST(%I - $1, 0) WHERE id = $2', v_attribute, v_attribute)
      USING v_log.xp_earned, p_user_id;
  END IF;

  SELECT r.rank_name, r.sub_rank INTO v_rank, v_sub
    FROM public.resolve_specialization_rank(v_focus_type, COALESCE(v_spec_xp, 0)) r;
  UPDATE public.users SET rank = v_rank, rank_sub_index = v_sub WHERE id = p_user_id;

  RETURN jsonb_build_object('success', TRUE, 'deleted', p_log_id, 'xp_removed', v_log.xp_earned,
                            'rank', v_rank, 'rank_sub_index', v_sub);
END;
$$;

ALTER FUNCTION public.delete_workout_log(uuid, uuid) OWNER TO postgres;
-- The project rule for every new function: closed to the public API, reached only through Edge Functions.
REVOKE EXECUTE ON FUNCTION public.delete_workout_log(uuid, uuid) FROM PUBLIC, anon, authenticated;
