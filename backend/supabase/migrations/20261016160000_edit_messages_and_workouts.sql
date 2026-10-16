-- Editing: messages get an "edited" marker, and a hand-logged workout can be corrected.

ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS edited_at timestamp without time zone;  -- UTC, like created_at
ALTER TABLE public.direct_messages ADD COLUMN IF NOT EXISTS edited_at timestamp with time zone;

-- Correct a workout's sets, reps, weight or time. XP, rank, attribute points and the strength record
-- depend on those numbers, so an edit is "take the old workout back, log the new one" inside ONE
-- transaction (any failure rolls both halves back): delete_workout_log enforces who and when
-- (manual, under 24 hours, not a mission/dungeon set, same path), log_workout_and_progress
-- validates the new numbers and pays XP exactly as a fresh log would. The original time is kept, so
-- editing does not extend the 24-hour window. The exercise itself can't change: delete and re-log.
CREATE OR REPLACE FUNCTION public.edit_workout_log(
  p_user_id uuid, p_log_id uuid, p_sets integer, p_reps integer, p_weight_kg numeric, p_duration_seconds integer
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_old public.workout_logs%ROWTYPE;
  v_new jsonb;
BEGIN
  SELECT * INTO v_old FROM public.workout_logs WHERE id = p_log_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LOG_NOT_FOUND: That workout was not found.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.delete_workout_log(p_user_id, p_log_id);
  v_new := public.log_workout_and_progress(
    p_user_id, v_old.exercise, p_sets, p_reps, NULL, 'manual', p_weight_kg, p_duration_seconds, v_old.distance_m);
  UPDATE public.workout_logs SET logged_at = v_old.logged_at WHERE id = (v_new->>'workout_log_id')::uuid;

  RETURN v_new || jsonb_build_object('previous_xp', v_old.xp_earned);
END;
$$;
ALTER FUNCTION public.edit_workout_log(uuid, uuid, integer, integer, numeric, integer) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.edit_workout_log(uuid, uuid, integer, integer, numeric, integer) FROM PUBLIC, anon, authenticated;
