-- AWXCEND baseline schema, copied 2026-09-26 from the original AWXCEND project.
-- Schema only: tables, functions, triggers, RLS policies and grants of the public schema.
-- No rows are created here; reference data is the next migration. No user data is ever copied.

-- Food search uses trigram indexes (foods_search_text_trgm).
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."abandon_mission_attempt"("p_user_id" "uuid", "p_attempt_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  UPDATE public.mission_attempts
     SET status = 'abandoned', ended_at = now()
   WHERE id = p_attempt_id AND user_id = p_user_id AND status = 'active';

  RETURN jsonb_build_object('success', TRUE, 'abandoned', FOUND);
END;
$$;


ALTER FUNCTION "public"."abandon_mission_attempt"("p_user_id" "uuid", "p_attempt_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_cancel_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_event  public.dungeon_events;
  v_tiers  JSONB;
  v_run    RECORD;
  v_pct    NUMERIC;
  v_xp     INTEGER;
  v_gold   INTEGER;
  v_paid   INTEGER := 0;
BEGIN
  PERFORM public.assert_can_manage_dungeons(p_admin_id);

  SELECT * INTO v_event FROM public.dungeon_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND: no Dungeon with that id' USING ERRCODE = 'P0001';
  END IF;
  IF v_event.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', TRUE, 'already_cancelled', TRUE);
  END IF;

  SELECT value->'tiers' INTO v_tiers FROM public.game_config WHERE key = 'dungeon_consolation';

  -- Every player who was in a battle that had started gets something, scaled
  -- by the damage their party had done to the boss.
  FOR v_run IN
    SELECT r.id, r.user_id, b.boss_hp, e.boss_max_hp
      FROM public.dungeon_runs r
      JOIN public.dungeon_battles b ON b.id = r.battle_id
      JOIN public.dungeon_events e ON e.id = b.event_id
     WHERE b.event_id = p_event_id
       AND b.status IN ('active', 'paused')
       AND r.status <> 'quit'
  LOOP
    v_pct := CASE WHEN v_run.boss_max_hp > 0
                  THEN ((v_run.boss_max_hp - v_run.boss_hp)::NUMERIC / v_run.boss_max_hp) * 100
                  ELSE 0 END;

    SELECT (t->>'xp')::INTEGER, (t->>'gold')::INTEGER
      INTO v_xp, v_gold
      FROM jsonb_array_elements(v_tiers) t
     WHERE (t->>'min_percent')::NUMERIC <= v_pct
     ORDER BY (t->>'min_percent')::NUMERIC DESC
     LIMIT 1;

    IF COALESCE(v_xp, 0) > 0 THEN
      PERFORM public.grant_bonus_xp(v_run.user_id, v_xp, 'dungeon_consolation', p_event_id);
    END IF;
    IF COALESCE(v_gold, 0) > 0 THEN
      PERFORM public.award_gold(
        v_run.user_id, v_gold, 'dungeon_consolation', p_event_id,
        format('dungeon_consolation:%s:%s', p_event_id, v_run.user_id)
      );
    END IF;

    UPDATE public.dungeon_runs
       SET status = 'failed', ended_at = now(), contribution_percent = v_pct
     WHERE id = v_run.id;

    v_paid := v_paid + 1;
  END LOOP;

  UPDATE public.dungeon_battles
     SET status = 'cancelled', ended_at = now()
   WHERE event_id = p_event_id AND status IN ('forming', 'active', 'paused');

  UPDATE public.dungeon_events
     SET status = 'cancelled', cancelled_at = now()
   WHERE id = p_event_id;

  RETURN jsonb_build_object('success', TRUE, 'cancelled', TRUE, 'players_compensated', v_paid);
END;
$$;


ALTER FUNCTION "public"."admin_cancel_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_dungeon_event"("p_admin_id" "uuid", "p_payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_id    UUID;
  v_boss  UUID;
  v_rank  TEXT := COALESCE(p_payload->>'threat_rank', 'C');
  v_hp    INTEGER := COALESCE((p_payload->>'boss_max_hp')::INTEGER, 600);
  v_diff  TEXT := COALESCE(p_payload->>'difficulty', 'medium');
BEGIN
  PERFORM public.assert_can_manage_dungeons(p_admin_id);

  IF COALESCE(p_payload->>'name', '') = '' THEN
    RAISE EXCEPTION 'INVALID_NAME: a Dungeon needs a name' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.threat_ranks WHERE key = v_rank) THEN
    RAISE EXCEPTION 'INVALID_RANK: % is not a threat rank', v_rank USING ERRCODE = 'P0001';
  END IF;
  IF v_hp < 50 OR v_hp > 100000 THEN
    RAISE EXCEPTION 'INVALID_HP: boss HP must be between 50 and 100000' USING ERRCODE = 'P0001';
  END IF;

  -- An existing boss by key, or a new one named after the Dungeon.
  IF p_payload ? 'boss_key' THEN
    SELECT id INTO v_boss FROM public.bosses WHERE key = p_payload->>'boss_key';
  END IF;
  IF v_boss IS NULL THEN
    INSERT INTO public.bosses (key, name, lore)
    VALUES (
      COALESCE(p_payload->>'boss_key', 'dungeon_' || left(md5(random()::text), 8)),
      COALESCE(p_payload->>'boss_name', p_payload->>'name'),
      p_payload->>'boss_lore'
    )
    ON CONFLICT (key) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_boss;
  END IF;

  INSERT INTO public.dungeon_events (
    name, threat_rank, boss_id, boss_max_hp, difficulty, config, created_by, status
  ) VALUES (
    p_payload->>'name', v_rank, v_boss, v_hp, v_diff,
    COALESCE(p_payload->'config', '{}'::jsonb) || jsonb_build_object(
      'potions', COALESCE(p_payload->'config'->'potions',
                          '{"health_potion": true, "revive_potion": true, "rest_potion": true}'::jsonb),
      'min_contribution_percent', COALESCE((p_payload->'config'->>'min_contribution_percent')::NUMERIC, 10),
      'reward_xp', COALESCE((p_payload->'config'->>'reward_xp')::INTEGER, 600),
      'reward_gold', COALESCE((p_payload->'config'->>'reward_gold')::INTEGER, 90),
      'open_to_all', COALESCE((p_payload->'config'->>'open_to_all')::BOOLEAN, TRUE)
    ),
    p_admin_id, 'draft'
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', TRUE, 'event_id', v_id, 'status', 'draft');
END;
$$;


ALTER FUNCTION "public"."admin_create_dungeon_event"("p_admin_id" "uuid", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_food_json"("p_food_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT (to_jsonb(f) - 'search_text') || jsonb_build_object(
    'servings', coalesce((
      SELECT jsonb_agg(jsonb_build_object('label', s.label, 'grams', s.grams, 'is_estimate', s.is_estimate) ORDER BY s.sort_order, s.label)
        FROM public.food_servings s WHERE s.food_id = f.id), '[]'::jsonb),
    'used_by_budget', EXISTS (SELECT 1 FROM public.market_commodities c WHERE c.food_id = f.id))
  FROM public.foods f
  WHERE f.id = p_food_id
$$;


ALTER FUNCTION "public"."admin_food_json"("p_food_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_dungeon_events"("p_admin_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_events JSONB;
BEGIN
  PERFORM public.assert_can_manage_dungeons(p_admin_id);

  SELECT jsonb_agg(
           jsonb_build_object(
             'id', e.id, 'name', e.name, 'threat_rank', e.threat_rank, 'status', e.status,
             'boss_name', b.name, 'boss_max_hp', e.boss_max_hp, 'difficulty', e.difficulty,
             'config', e.config, 'opens_at', e.opens_at, 'ends_at', e.ends_at,
             'created_at', e.created_at,
             'battles', (SELECT COUNT(*) FROM public.dungeon_battles db WHERE db.event_id = e.id),
             'clears', (SELECT COUNT(*) FROM public.dungeon_clears dc WHERE dc.event_id = e.id),
             'reward_pool', (
               SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'collectible_key', c.key, 'name', c.name, 'rarity', c.rarity,
                        'gold_amount', p.gold_amount, 'weight', p.weight) ORDER BY p.id), '[]'::jsonb)
                 FROM public.dungeon_reward_pool p
                 LEFT JOIN public.collectibles c ON c.id = p.collectible_id
                WHERE p.event_id = e.id)
           ) ORDER BY e.created_at DESC)
    INTO v_events
    FROM public.dungeon_events e
    LEFT JOIN public.bosses b ON b.id = e.boss_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'events', COALESCE(v_events, '[]'::jsonb),
    'threat_ranks', (SELECT jsonb_agg(jsonb_build_object('key', key, 'label', label, 'is_anomalous', is_anomalous)
                                        ORDER BY sort_order) FROM public.threat_ranks),
    'collectibles', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                              'key', c.key, 'name', c.name, 'kind', c.kind,
                              'rarity', c.rarity, 'gold_value', c.gold_value)
                            ORDER BY r.sort_order DESC, c.name), '[]'::jsonb)
                       FROM public.collectibles c
                       JOIN public.rarities r ON r.key = c.rarity
                      WHERE c.is_active)
  );
END;
$$;


ALTER FUNCTION "public"."admin_list_dungeon_events"("p_admin_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_foods"("p_query" "text" DEFAULT NULL::"text", "p_include_hidden" boolean DEFAULT false, "p_limit" integer DEFAULT 30, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  WITH q AS (
    SELECT lower(regexp_replace(trim(coalesce(p_query, '')), '[%_\\]', '', 'g')) AS t
  ),
  matched AS (
    SELECT f.id, f.name
      FROM public.foods f, q
     WHERE (coalesce(p_include_hidden, FALSE) OR f.active)
       AND (q.t = '' OR f.search_text LIKE '%' || q.t || '%' OR f.slug LIKE '%' || q.t || '%')
  ),
  page AS (
    SELECT id, name FROM matched
     ORDER BY lower(name), id
     LIMIT greatest(1, least(coalesce(p_limit, 30), 100))
    OFFSET greatest(0, coalesce(p_offset, 0))
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM matched),
    'items', coalesce((SELECT jsonb_agg(public.admin_food_json(p.id) ORDER BY lower(p.name), p.id) FROM page p), '[]'::jsonb))
$$;


ALTER FUNCTION "public"."admin_list_foods"("p_query" "text", "p_include_hidden" boolean, "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_verification_applications"("p_scope" "text", "p_limit" integer) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'user_id', a.user_id, 'username', u.username, 'kind', a.kind, 'status', a.status,
    'experience_summary', a.experience_summary, 'evidence_count', a.evidence_count,
    'evidence_hashes', to_jsonb(a.evidence_hashes), 'evidence_sizes', to_jsonb(a.evidence_sizes),
    'submitted_at', a.submitted_at, 'decided_at', a.decided_at, 'decided_by_username', d.username,
    'decision_reason', a.decision_reason, 'withdrawn_at', a.withdrawn_at, 'revoked_at', a.revoked_at,
    'revoked_by_self', a.revoked_by_self, 'revoke_reason', a.revoke_reason,
    'files_deleted', a.files_deleted_at IS NOT NULL
  ) ORDER BY a.submitted_at DESC), '[]'::jsonb)
  FROM (
    SELECT * FROM public.verification_applications
    WHERE (p_scope = 'pending' AND status = 'pending') OR (p_scope = 'decided' AND status <> 'pending')
    ORDER BY submitted_at DESC
    LIMIT least(greatest(coalesce(p_limit, 50), 1), 100)
  ) a
  LEFT JOIN public.users u ON u.id = a.user_id
  LEFT JOIN public.users d ON d.id = a.decided_by;
$$;


ALTER FUNCTION "public"."admin_list_verification_applications"("p_scope" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_open_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid", "p_duration_hours" numeric DEFAULT 24) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_event public.dungeon_events;
BEGIN
  PERFORM public.assert_can_manage_dungeons(p_admin_id);

  IF p_duration_hours IS NULL OR p_duration_hours < 1 OR p_duration_hours > 720 THEN
    RAISE EXCEPTION 'INVALID_DURATION: between 1 and 720 hours' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_event FROM public.dungeon_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND: no Dungeon with that id' USING ERRCODE = 'P0001';
  END IF;
  IF v_event.status <> 'draft' THEN
    RAISE EXCEPTION 'ALREADY_OPEN: this Dungeon is already %', v_event.status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.dungeon_events
     SET status = 'open',
         opens_at = now(),
         ends_at = now() + make_interval(hours => p_duration_hours::INTEGER,
                                         mins  => ((p_duration_hours - FLOOR(p_duration_hours)) * 60)::INTEGER)
   WHERE id = p_event_id;

  RETURN jsonb_build_object(
    'success', TRUE, 'event_id', p_event_id, 'status', 'open',
    'ends_at', (SELECT ends_at FROM public.dungeon_events WHERE id = p_event_id)
  );
END;
$$;


ALTER FUNCTION "public"."admin_open_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid", "p_duration_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_save_food"("p_food_id" "uuid", "p_expected_updated_at" timestamp with time zone, "p_food" "jsonb", "p_servings" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
DECLARE
  v_before          public.foods%ROWTYPE;
  v_before_json     JSONB;
  v_id              UUID;
  v_source          TEXT := p_food->>'source';
  v_reference       TEXT := btrim(coalesce(p_food->>'source_reference', ''));
  v_is_estimate     BOOLEAN := coalesce((p_food->>'is_estimate')::boolean, FALSE);
  v_calories        NUMERIC;
  v_protein         NUMERIC;
  v_carbs           NUMERIC;
  v_fat             NUMERIC;
  v_fiber           NUMERIC;
  v_sugar           NUMERIC;
  v_local_names     TEXT[];
  v_aliases         TEXT[];
  v_slug_base       TEXT;
  v_slug            TEXT;
  v_n               INTEGER := 1;
BEGIN
  IF p_food IS NULL OR jsonb_typeof(p_food) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_FOOD: food details are missing';
  END IF;
  IF v_source IS NULL OR v_source NOT IN ('label', 'manual_estimate', 'usda', 'usda_derived') THEN
    RAISE EXCEPTION 'SOURCE_NOT_ALLOWED: that nutrition source can''t be chosen here (PhilFCT needs written DOST-FNRI permission first)';
  END IF;
  IF v_reference = '' OR char_length(v_reference) > 300 THEN
    RAISE EXCEPTION 'INVALID_FOOD: a source reference of up to 300 characters is required';
  END IF;

  IF p_servings IS NULL THEN p_servings := '[]'::jsonb; END IF;
  IF jsonb_typeof(p_servings) <> 'array' OR jsonb_array_length(p_servings) > 8 THEN
    RAISE EXCEPTION 'INVALID_SERVINGS: up to 8 servings are allowed';
  END IF;

  IF jsonb_typeof(coalesce(p_food->'local_names', '[]'::jsonb)) <> 'array'
     OR jsonb_typeof(coalesce(p_food->'aliases', '[]'::jsonb)) <> 'array'
     OR jsonb_array_length(coalesce(p_food->'local_names', '[]'::jsonb)) > 10
     OR jsonb_array_length(coalesce(p_food->'aliases', '[]'::jsonb)) > 10 THEN
    RAISE EXCEPTION 'INVALID_FOOD: up to 10 local names and 10 other names are allowed';
  END IF;
  v_local_names := ARRAY(SELECT btrim(x) FROM jsonb_array_elements_text(coalesce(p_food->'local_names', '[]'::jsonb)) x WHERE btrim(x) <> '');
  v_aliases     := ARRAY(SELECT btrim(x) FROM jsonb_array_elements_text(coalesce(p_food->'aliases', '[]'::jsonb)) x WHERE btrim(x) <> '');
  IF EXISTS (SELECT 1 FROM unnest(v_local_names || v_aliases) n WHERE char_length(n) > 60) THEN
    RAISE EXCEPTION 'INVALID_FOOD: each name must be 60 characters or fewer';
  END IF;
  IF char_length(coalesce(p_food->>'brand', '')) > 80 THEN
    RAISE EXCEPTION 'INVALID_FOOD: brand must be 80 characters or fewer';
  END IF;
  IF char_length(coalesce(p_food->>'estimate_note', '')) > 500 THEN
    RAISE EXCEPTION 'INVALID_FOOD: estimate note must be 500 characters or fewer';
  END IF;

  -- Stored at one decimal, so compare at one decimal too.
  v_calories := round((p_food->>'calories')::numeric, 1);
  v_protein  := round((p_food->>'protein')::numeric, 1);
  v_carbs    := round((p_food->>'carbs')::numeric, 1);
  v_fat      := round((p_food->>'fat')::numeric, 1);
  v_fiber    := round(nullif(p_food->>'fiber', '')::numeric, 1);
  v_sugar    := round(nullif(p_food->>'sugar', '')::numeric, 1);
  IF v_calories IS NULL OR v_protein IS NULL OR v_carbs IS NULL OR v_fat IS NULL THEN
    RAISE EXCEPTION 'INVALID_FOOD: calories, protein, carbs and fat per 100 g are required';
  END IF;

  IF p_food_id IS NULL THEN
    -- Create. Serialise slug generation so two admins adding "Adobo" at the
    -- same moment get adobo and adobo-2, not a unique-violation.
    PERFORM pg_advisory_xact_lock(hashtext('public.foods.slug'));
    v_slug_base := coalesce(p_food->>'slug', '');
    IF v_slug_base !~ '^[a-z0-9]+(-[a-z0-9]+)*$' OR char_length(v_slug_base) > 60 THEN
      RAISE EXCEPTION 'INVALID_FOOD: the food id could not be made from its name';
    END IF;
    v_slug := v_slug_base;
    WHILE EXISTS (SELECT 1 FROM public.foods WHERE slug = v_slug) LOOP
      v_n := v_n + 1;
      v_slug := v_slug_base || '-' || v_n;
    END LOOP;

    INSERT INTO public.foods (
      slug, name, description, local_names, aliases, category, region, preparation, brand,
      calories, protein, carbs, fat, fiber, sugar,
      source, source_reference, is_estimate, estimate_note, active
    ) VALUES (
      v_slug, btrim(p_food->>'name'), nullif(btrim(coalesce(p_food->>'description', '')), ''),
      v_local_names, v_aliases, p_food->>'category', p_food->>'region',
      nullif(p_food->>'preparation', ''), nullif(btrim(coalesce(p_food->>'brand', '')), ''),
      v_calories, v_protein, v_carbs, v_fat, v_fiber, v_sugar,
      v_source, v_reference, v_is_estimate,
      CASE WHEN v_is_estimate THEN nullif(btrim(coalesce(p_food->>'estimate_note', '')), '') END,
      TRUE
    )
    RETURNING id INTO v_id;
  ELSE
    SELECT * INTO v_before FROM public.foods WHERE id = p_food_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'FOOD_NOT_FOUND: that food no longer exists';
    END IF;
    -- Millisecond precision: the editor round-trips the timestamp through
    -- JavaScript, which keeps milliseconds only.
    IF p_expected_updated_at IS NULL
       OR date_trunc('milliseconds', v_before.updated_at) <> date_trunc('milliseconds', p_expected_updated_at) THEN
      RAISE EXCEPTION 'STALE_EDIT: this food was changed by someone else while you were editing. Reopen it to see the latest version';
    END IF;

    IF (v_before.calories IS DISTINCT FROM v_calories OR v_before.protein IS DISTINCT FROM v_protein
        OR v_before.carbs IS DISTINCT FROM v_carbs OR v_before.fat IS DISTINCT FROM v_fat
        OR v_before.fiber IS DISTINCT FROM v_fiber OR v_before.sugar IS DISTINCT FROM v_sugar)
       AND v_before.source = v_source
       AND btrim(v_before.source_reference) = v_reference THEN
      RAISE EXCEPTION 'PROVENANCE_REQUIRED: you changed the nutrition values, so update where they come from too (source or reference)';
    END IF;

    v_before_json := public.admin_food_json(p_food_id);

    UPDATE public.foods SET
      name = btrim(p_food->>'name'),
      description = nullif(btrim(coalesce(p_food->>'description', '')), ''),
      local_names = v_local_names,
      aliases = v_aliases,
      category = p_food->>'category',
      region = p_food->>'region',
      preparation = nullif(p_food->>'preparation', ''),
      brand = nullif(btrim(coalesce(p_food->>'brand', '')), ''),
      calories = v_calories, protein = v_protein, carbs = v_carbs, fat = v_fat,
      fiber = v_fiber, sugar = v_sugar,
      source = v_source,
      source_reference = v_reference,
      is_estimate = v_is_estimate,
      estimate_note = CASE WHEN v_is_estimate THEN nullif(btrim(coalesce(p_food->>'estimate_note', '')), '') END
    WHERE id = p_food_id;
    v_id := p_food_id;

    DELETE FROM public.food_servings WHERE food_id = v_id;
  END IF;

  -- A serving weight typed from a nutrition label is the label's; any other
  -- serving weight an admin types is an estimate.
  INSERT INTO public.food_servings (food_id, label, grams, is_estimate, sort_order)
  SELECT v_id, btrim(s.e->>'label'), round((s.e->>'grams')::numeric, 1), v_source <> 'label', s.ord::integer
    FROM jsonb_array_elements(p_servings) WITH ORDINALITY AS s(e, ord);

  RETURN jsonb_build_object(
    'created', p_food_id IS NULL,
    'food', public.admin_food_json(v_id),
    'before', v_before_json);
END;
$_$;


ALTER FUNCTION "public"."admin_save_food"("p_food_id" "uuid", "p_expected_updated_at" timestamp with time zone, "p_food" "jsonb", "p_servings" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_dungeon_reward_pool"("p_admin_id" "uuid", "p_event_id" "uuid", "p_entries" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_e      JSONB;
  v_count  INTEGER := 0;
  v_cid    UUID;
  v_gold   INTEGER;
BEGIN
  PERFORM public.assert_can_manage_dungeons(p_admin_id);

  IF NOT EXISTS (SELECT 1 FROM public.dungeon_events WHERE id = p_event_id) THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND: no Dungeon with that id' USING ERRCODE = 'P0001';
  END IF;

  -- Replaced wholesale rather than merged: a pool is easier to reason about
  -- when the admin sees exactly what they submitted.
  DELETE FROM public.dungeon_reward_pool WHERE event_id = p_event_id;

  FOR v_e IN SELECT * FROM jsonb_array_elements(COALESCE(p_entries, '[]'::jsonb)) LOOP
    v_cid := NULL;
    v_gold := NULL;

    IF v_e ? 'collectible_key' THEN
      SELECT id INTO v_cid FROM public.collectibles WHERE key = v_e->>'collectible_key';
      IF v_cid IS NULL THEN
        RAISE EXCEPTION 'UNKNOWN_ITEM: there is no collectible called %', v_e->>'collectible_key'
          USING ERRCODE = 'P0001';
      END IF;
    ELSIF v_e ? 'gold_amount' THEN
      v_gold := (v_e->>'gold_amount')::INTEGER;
      IF v_gold IS NULL OR v_gold <= 0 THEN
        RAISE EXCEPTION 'INVALID_GOLD: a gold entry must be a positive amount' USING ERRCODE = 'P0001';
      END IF;
    ELSE
      RAISE EXCEPTION 'INVALID_ENTRY: each entry needs a collectible_key or a gold_amount'
        USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.dungeon_reward_pool (event_id, collectible_id, gold_amount, weight)
    VALUES (p_event_id, v_cid, v_gold, GREATEST(COALESCE((v_e->>'weight')::INTEGER, 1), 1));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'entries', v_count);
END;
$$;


ALTER FUNCTION "public"."admin_set_dungeon_reward_pool"("p_admin_id" "uuid", "p_event_id" "uuid", "p_entries" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_food_active"("p_food_id" "uuid", "p_active" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_food public.foods%ROWTYPE;
BEGIN
  IF p_active IS NULL THEN
    RAISE EXCEPTION 'INVALID_FOOD: say whether the food should be shown or hidden';
  END IF;
  SELECT * INTO v_food FROM public.foods WHERE id = p_food_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FOOD_NOT_FOUND: that food no longer exists';
  END IF;
  IF v_food.active = p_active THEN
    RETURN jsonb_build_object('changed', FALSE, 'food', public.admin_food_json(p_food_id));
  END IF;
  UPDATE public.foods SET active = p_active WHERE id = p_food_id;
  RETURN jsonb_build_object('changed', TRUE, 'food', public.admin_food_json(p_food_id));
END;
$$;


ALTER FUNCTION "public"."admin_set_food_active"("p_food_id" "uuid", "p_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_reference_price"("p_commodity_slug" "text", "p_price_php" numeric, "p_note" "text", "p_day" "date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_commodity public.market_commodities%ROWTYPE;
  v_before    NUMERIC;
  v_row       public.commodity_reference_prices%ROWTYPE;
BEGIN
  SELECT * INTO v_commodity FROM public.market_commodities WHERE slug = p_commodity_slug AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'UNKNOWN_COMMODITY: that item isn''t in the price list.';
  END IF;

  SELECT r.price_php INTO v_before
  FROM public.commodity_reference_prices r
  WHERE r.commodity_id = v_commodity.id
  ORDER BY r.period_end DESC, r.created_at DESC
  LIMIT 1;

  INSERT INTO public.commodity_reference_prices (
    commodity_id, unit, price_php, region, period_start, period_end,
    source, source_label, source_reference, source_item, specification, note, created_at
  ) VALUES (
    v_commodity.id, v_commodity.purchase_unit, round(p_price_php, 2), 'NCR', p_day, p_day,
    'admin_adjustment', 'Adjusted by a GYMORA admin', NULL, v_commodity.name, NULL, btrim(p_note),
    -- clock_timestamp, not now(): two adjustments in one transaction must still order.
    clock_timestamp()
  )
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'commodity', v_commodity.slug, 'name', v_commodity.name, 'unit', v_row.unit,
    'price_php', v_row.price_php, 'previous_price_php', v_before,
    'day', v_row.period_start, 'note', v_row.note
  );
END;
$$;


ALTER FUNCTION "public"."admin_set_reference_price"("p_commodity_slug" "text", "p_price_php" numeric, "p_note" "text", "p_day" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_xp_gain"("p_user_id" "uuid", "p_xp" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_previous_xp   INTEGER;
  v_previous_rank TEXT;
  v_previous_sub  INTEGER;
  v_focus_type    TEXT;

  v_new_total_xp  INTEGER;
  v_spec_new_xp   INTEGER;
  v_spec_prev_xp  INTEGER;

  v_current_rank  TEXT;
  v_current_tier  INTEGER;
  v_current_sub   INTEGER;
  v_next_rank     TEXT;
  v_next_min_xp   INTEGER;
  v_to_next_sub   INTEGER;
  v_level_up      BOOLEAN := FALSE;
  v_sub_rank_up   BOOLEAN := FALSE;
BEGIN
  IF p_xp IS NULL OR p_xp < 0 THEN
    RAISE EXCEPTION 'INVALID_XP: xp must be zero or positive, got %', p_xp
      USING ERRCODE = 'P0001';
  END IF;

  SELECT xp, rank, rank_sub_index, focus_type
    INTO v_previous_xp, v_previous_rank, v_previous_sub, v_focus_type
    FROM public.users
   WHERE id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: no user with id %', p_user_id
      USING ERRCODE = 'P0002';
  END IF;

  -- users.xp stays the lifetime figure behind Level and the consistency
  -- leaderboard; the per-path total is what rank reads from.
  v_new_total_xp := v_previous_xp + p_xp;

  UPDATE public.users SET xp = v_new_total_xp WHERE id = p_user_id;

  INSERT INTO public.user_specialization_xp (user_id, focus_type, xp)
  VALUES (p_user_id, v_focus_type, p_xp)
  ON CONFLICT (user_id, focus_type) DO UPDATE
    SET xp = public.user_specialization_xp.xp + EXCLUDED.xp,
        updated_at = now()
  RETURNING xp, xp - p_xp INTO v_spec_new_xp, v_spec_prev_xp;

  -- resolve_specialization_rank RAISES when a focus_type has no ladder rows,
  -- rather than silently freezing the user at their previous rank.
  SELECT r.rank_name, r.tier_index, r.sub_rank,
         r.next_rank_name, r.next_tier_min_xp, r.xp_to_next_sub_rank
    INTO v_current_rank, v_current_tier, v_current_sub,
         v_next_rank, v_next_min_xp, v_to_next_sub
    FROM public.resolve_specialization_rank(v_focus_type, v_spec_new_xp) r;

  IF v_current_rank IS DISTINCT FROM v_previous_rank THEN
    v_level_up := TRUE;
  END IF;
  IF v_current_sub IS DISTINCT FROM v_previous_sub OR v_level_up THEN
    v_sub_rank_up := TRUE;
  END IF;

  IF v_level_up OR v_sub_rank_up THEN
    UPDATE public.users
       SET rank = v_current_rank,
           rank_sub_index = v_current_sub
     WHERE id = p_user_id;
  END IF;

  IF v_level_up THEN
    INSERT INTO public.rank_history (user_id, old_rank, new_rank)
      VALUES (p_user_id, v_previous_rank, v_current_rank);
  END IF;

  RETURN jsonb_build_object(
    'focus_type',          v_focus_type,
    'total_xp',            v_new_total_xp,
    'specialization_xp',   v_spec_new_xp,
    'previous_rank',       v_previous_rank,
    'current_rank',        v_current_rank,
    'rank_tier',           v_current_tier,
    'rank_sub_index',      v_current_sub,
    'level_up_triggered',  v_level_up,
    'sub_rank_changed',    v_sub_rank_up,
    'next_rank',           v_next_rank,
    'xp_to_next_rank',     COALESCE(v_next_min_xp - v_spec_new_xp, 0),
    'xp_to_next_sub_rank', v_to_next_sub
  );
END;
$$;


ALTER FUNCTION "public"."apply_xp_gain"("p_user_id" "uuid", "p_xp" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_camera_objective_eligible"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NOT public.camera_reward_eligible(NEW.exercise) THEN
    RAISE EXCEPTION 'CAMERA_NOT_VALIDATED: "%" cannot be a % objective — its camera tracker is not validated, authorised and XP-configured', NEW.exercise, TG_TABLE_NAME
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."assert_camera_objective_eligible"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_can_manage_dungeons"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id = p_user_id;
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: only an admin can manage Dungeon events' USING ERRCODE = 'P0001';
  END IF;
END;
$$;


ALTER FUNCTION "public"."assert_can_manage_dungeons"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_mission_is_clearable"("p_mission_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_min_multiplier NUMERIC;
  v_total_damage   NUMERIC;
  v_max_hp         INTEGER;
BEGIN
  v_min_multiplier := COALESCE(
    (SELECT (value->>'min_multiplier')::NUMERIC FROM public.game_config WHERE key = 'form_damage'),
    1.0
  );

  SELECT max_hp INTO v_max_hp FROM public.missions WHERE id = p_mission_id;

  SELECT COALESCE(SUM(base_damage), 0)
    INTO v_total_damage
    FROM public.mission_objectives
   WHERE mission_id = p_mission_id;

  IF v_total_damage * v_min_multiplier < v_max_hp THEN
    RAISE EXCEPTION
      'MISSION_NOT_CLEARABLE: boss HP % exceeds the % damage all objectives can guarantee (% base damage x % worst-case form)',
      v_max_hp, v_total_damage * v_min_multiplier, v_total_damage, v_min_multiplier
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;


ALTER FUNCTION "public"."assert_mission_is_clearable"("p_mission_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_result_plausible"("p_exercise" "text", "p_metric_type" "text", "p_achieved" numeric, "p_elapsed_s" numeric) RETURNS "void"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_cfg       JSONB;
  v_per_rep   NUMERIC;
  v_tolerance NUMERIC;
  v_required  NUMERIC;
BEGIN
  SELECT value INTO v_cfg FROM public.game_config WHERE key = 'plausibility';
  v_tolerance := COALESCE((v_cfg->>'duration_tolerance_seconds')::NUMERIC, 5);

  IF p_metric_type = 'duration' THEN
    IF p_achieved > COALESCE(p_elapsed_s, 0) + v_tolerance THEN
      RAISE EXCEPTION 'IMPLAUSIBLE_RESULT: % seconds claimed but only % seconds have passed',
        p_achieved, ROUND(COALESCE(p_elapsed_s, 0))
        USING ERRCODE = 'P0001';
    END IF;
    RETURN;
  END IF;

  v_per_rep := COALESCE(
    (v_cfg->'min_seconds_per_rep'->>p_exercise)::NUMERIC,
    (v_cfg->>'default_min_seconds_per_rep')::NUMERIC,
    0.8
  );
  v_required := p_achieved * v_per_rep;

  -- One second of slack for clock skew between the device and the server.
  IF COALESCE(p_elapsed_s, 0) + 1 < v_required THEN
    RAISE EXCEPTION 'IMPLAUSIBLE_RESULT: % reps need at least % seconds, but only % have passed',
      p_achieved, ROUND(v_required, 1), ROUND(COALESCE(p_elapsed_s, 0))
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;


ALTER FUNCTION "public"."assert_result_plausible"("p_exercise" "text", "p_metric_type" "text", "p_achieved" numeric, "p_elapsed_s" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_dungeon_objective"("p_battle_id" "uuid", "p_run_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_cfg      JSONB;
  v_diff     TEXT;
  v_exercise TEXT;
  v_metric   TEXT;
  v_target   NUMERIC;
  v_damage   INTEGER;
  v_ordinal  INTEGER;
  v_id       UUID;
BEGIN
  SELECT value INTO v_cfg FROM public.game_config WHERE key = 'dungeon_objectives';

  SELECT e.difficulty INTO v_diff
    FROM public.dungeon_battles b JOIN public.dungeon_events e ON e.id = b.event_id
   WHERE b.id = p_battle_id;

  SELECT COUNT(*) INTO v_ordinal FROM public.dungeon_assignments WHERE run_id = p_run_id;

  v_exercise := public.pick_dungeon_exercise(p_battle_id, p_run_id, v_ordinal);
  IF v_exercise IS NULL THEN
    RETURN jsonb_build_object('assigned', FALSE, 'reason', 'every movement is taken by a teammate right now');
  END IF;

  SELECT metric_type INTO v_metric FROM public.exercises WHERE name = v_exercise;
  v_target := CASE
    WHEN v_metric = 'duration' THEN COALESCE((v_cfg->'duration_target'->>v_diff)::NUMERIC, 60)
    ELSE COALESCE((v_cfg->'reps_target'->>v_diff)::NUMERIC, 25)
  END;
  v_damage := COALESCE((v_cfg->'base_damage'->>v_diff)::INTEGER, 100);

  INSERT INTO public.dungeon_assignments (
    battle_id, run_id, exercise, target_value, base_damage, difficulty, status
  ) VALUES (
    p_battle_id, p_run_id, v_exercise, v_target, v_damage, v_diff, 'active'
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'assigned', TRUE, 'assignment_id', v_id, 'exercise', v_exercise,
    'metric_type', v_metric, 'target_value', v_target, 'base_damage', v_damage
  );
END;
$$;


ALTER FUNCTION "public"."assign_dungeon_objective"("p_battle_id" "uuid", "p_run_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."award_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid" DEFAULT NULL::"uuid", "p_idempotency_key" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: an award must be positive, got %', p_amount
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.gold_ledger (user_id, amount, reason, source_id, idempotency_key)
  VALUES (p_user_id, p_amount, p_reason, p_source_id, p_idempotency_key)
  ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'awarded',   v_id IS NOT NULL,
    'duplicate', v_id IS NULL,
    'amount',    CASE WHEN v_id IS NULL THEN 0 ELSE p_amount END,
    'ledger_id', v_id,
    'balance',   public.gold_balance(p_user_id)
  );
END;
$$;


ALTER FUNCTION "public"."award_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid", "p_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."begin_coach_application"("p_application_id" "uuid", "p_user_id" "uuid", "p_summary" "text", "p_hashes" "text"[], "p_sizes" integer[], "p_notice_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_block JSONB;
BEGIN
  IF NOT public.has_current_consent(p_user_id, 'verification')
     OR p_notice_version IS DISTINCT FROM public.current_notice_version('verification') THEN
    RAISE EXCEPTION 'CONSENT_REQUIRED: please read the current verification notice first';
  END IF;

  v_block := public.coach_application_block(p_user_id);
  IF v_block IS NOT NULL THEN
    RAISE EXCEPTION '%: %', v_block->>'code', CASE v_block->>'code'
      WHEN 'APPLICATION_PENDING' THEN 'you already have an application waiting for review'
      WHEN 'ALREADY_VERIFIED' THEN 'you are already a verified coach'
      ELSE 'you can apply again 7 days after a rejection' END;
  END IF;

  INSERT INTO public.verification_applications
    (id, user_id, kind, experience_summary, evidence_count, evidence_hashes, evidence_sizes, notice_version)
  VALUES
    (p_application_id, p_user_id, 'coach', p_summary, cardinality(p_hashes), p_hashes, p_sizes, p_notice_version);

  RETURN jsonb_build_object('application_id', p_application_id, 'status', 'pending');
END;
$$;


ALTER FUNCTION "public"."begin_coach_application"("p_application_id" "uuid", "p_user_id" "uuid", "p_summary" "text", "p_hashes" "text"[], "p_sizes" integer[], "p_notice_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."camera_lifecycle_validated"("p_exercise" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  -- An unknown exercise, a missing config row or an unrecognised stage all
  -- come out false: this fails closed.
  SELECT COALESCE(
    (SELECT value ->> p_exercise FROM public.game_config WHERE key = 'camera_exercise_lifecycle')
      IN ('validated', 'production'),
    FALSE)
$$;


ALTER FUNCTION "public"."camera_lifecycle_validated"("p_exercise" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."camera_reward_eligible"("p_exercise" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT
        EXISTS (SELECT 1 FROM public.exercises e WHERE e.name = p_exercise)
    AND COALESCE(
          (SELECT value ? p_exercise FROM public.game_config WHERE key = 'camera_trackable'),
          FALSE)
    AND public.camera_lifecycle_validated(p_exercise)
    AND EXISTS (SELECT 1 FROM public.xp_config x
                 WHERE x.workout_source = 'camera' AND x.exercise_name = p_exercise)
$$;


ALTER FUNCTION "public"."camera_reward_eligible"("p_exercise" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."camera_reward_eligible_exercises"() RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT ARRAY(
    SELECT x
      FROM jsonb_array_elements_text(
             COALESCE((SELECT value FROM public.game_config WHERE key = 'camera_trackable'), '[]'::jsonb)
           ) AS x
     WHERE public.camera_reward_eligible(x)
     ORDER BY x
  )
$$;


ALTER FUNCTION "public"."camera_reward_eligible_exercises"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle public.dungeon_battles;
  v_event  public.dungeon_events;
  v_rules  JSONB;
  v_cap    INTEGER;
  v_size   INTEGER;
  v_friend BOOLEAN;
BEGIN
  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'BATTLE_NOT_FOUND', 'reason', 'That party no longer exists.');
  END IF;

  SELECT * INTO v_event FROM public.dungeon_events WHERE id = v_battle.event_id;

  IF v_battle.status <> 'forming' THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'ALREADY_STARTED',
      'reason', 'That fight has already begun — nobody can join once it starts.');
  END IF;
  IF v_event.status <> 'open' OR (v_event.ends_at IS NOT NULL AND v_event.ends_at <= now()) THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'EVENT_CLOSED', 'reason', 'This Dungeon is no longer open.');
  END IF;

  -- Deactivated accounts are out of gameplay entirely.
  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id AND deactivated_at IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'DEACTIVATED', 'reason', 'This account is deactivated.');
  END IF;

  -- The event gate.
  IF NOT COALESCE((v_event.config->>'open_to_all')::BOOLEAN, TRUE)
     AND NOT EXISTS (SELECT 1 FROM public.dungeon_event_invites
                      WHERE event_id = v_event.id AND user_id = p_user_id) THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'NOT_INVITED', 'reason', 'This Dungeon is invitation only.');
  END IF;

  -- One live run per player per event — this is also what stops rejoining
  -- after quitting.
  IF EXISTS (
    SELECT 1 FROM public.dungeon_runs
     WHERE event_id = v_event.id AND user_id = p_user_id
       AND status IN ('joined', 'ready', 'active', 'disconnected', 'downed')
  ) THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'ALREADY_IN_BATTLE',
      'reason', 'You already have a run open in this Dungeon.');
  END IF;

  SELECT value INTO v_rules FROM public.game_config WHERE key = 'dungeon_rules';
  v_cap := COALESCE((v_event.config->>'party_max')::INTEGER,
                    (v_rules->>'party_max')::INTEGER, 4);
  SELECT COUNT(*) INTO v_size FROM public.dungeon_runs WHERE battle_id = p_battle_id;

  IF v_size >= v_cap THEN
    RETURN jsonb_build_object('ok', FALSE, 'code', 'PARTY_FULL',
      'reason', format('That party is full (%s of %s).', v_size, v_cap));
  END IF;

  -- The party gate.
  IF COALESCE((v_event.config->>'party_join_requires_friend')::BOOLEAN,
              (v_rules->>'party_join_requires_friend')::BOOLEAN, TRUE) THEN
    -- friendships is directional in storage (requester/addressee) but not in
    -- meaning once accepted, so both directions count.
    SELECT EXISTS (
      SELECT 1 FROM public.friendships f
       WHERE f.status = 'accepted'
         AND ((f.requester_id = p_user_id AND f.addressee_id = v_battle.leader_id)
           OR (f.addressee_id = p_user_id AND f.requester_id = v_battle.leader_id))
    ) INTO v_friend;

    IF NOT v_friend AND v_battle.leader_id IS DISTINCT FROM p_user_id THEN
      RETURN jsonb_build_object('ok', FALSE, 'code', 'NOT_A_FRIEND',
        'reason', 'You can only join a party led by one of your friends.');
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', TRUE, 'party_size', v_size, 'party_max', v_cap);
END;
$$;


ALTER FUNCTION "public"."can_join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_rate_limit"("p_user_id" "uuid", "p_action" "text", "p_max" integer, "p_window_seconds" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_now   timestamptz := now();
  v_count integer;
begin
  insert into public.rate_limits (user_id, action, window_start, count)
  values (p_user_id, p_action, v_now, 1)
  on conflict (user_id, action) do update
    set
      -- Window elapsed → start a fresh window at 1; otherwise increment.
      count = case
        when public.rate_limits.window_start < v_now - make_interval(secs => p_window_seconds)
          then 1
        else public.rate_limits.count + 1
      end,
      window_start = case
        when public.rate_limits.window_start < v_now - make_interval(secs => p_window_seconds)
          then v_now
        else public.rate_limits.window_start
      end
  returning count into v_count;

  return v_count <= p_max;
end;
$$;


ALTER FUNCTION "public"."check_rate_limit"("p_user_id" "uuid", "p_action" "text", "p_max" integer, "p_window_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_application_block"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.verification_applications
                  WHERE user_id = p_user_id AND kind = 'coach' AND status = 'pending')
      THEN jsonb_build_object('code', 'APPLICATION_PENDING')
    WHEN EXISTS (SELECT 1 FROM public.verification_applications
                  WHERE user_id = p_user_id AND kind = 'coach' AND status = 'approved')
      THEN jsonb_build_object('code', 'ALREADY_VERIFIED')
    WHEN EXISTS (SELECT 1 FROM public.verification_applications
                  WHERE user_id = p_user_id AND kind = 'coach' AND status = 'rejected'
                    AND decided_at > now() - interval '7 days')
      THEN jsonb_build_object('code', 'REJECTION_COOLDOWN', 'until', (
             SELECT max(decided_at) + interval '7 days' FROM public.verification_applications
             WHERE user_id = p_user_id AND kind = 'coach' AND status = 'rejected'))
    ELSE NULL
  END;
$$;


ALTER FUNCTION "public"."coach_application_block"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."compute_streak"("p_user_id" "uuid", "p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_tz           TEXT := public.game_timezone();
  v_today        DATE;
  v_last_counted DATE;
  v_last_trained DATE;
  v_streak       INTEGER := 0;
BEGIN
  v_today := (p_now AT TIME ZONE v_tz)::DATE;

  -- workout_logs.logged_at is a naive timestamp holding UTC, so it is
  -- anchored to UTC before being converted into the game's zone.
  WITH training_days AS (
    SELECT DISTINCT ((w.logged_at AT TIME ZONE 'UTC') AT TIME ZONE v_tz)::DATE AS day
      FROM public.workout_logs w
     WHERE w.user_id = p_user_id
  ),
  counted_days AS (
    SELECT day FROM training_days
    UNION
    SELECT s.covered_date FROM public.streak_shields s WHERE s.user_id = p_user_id
  ),
  ordered AS (
    SELECT day, ROW_NUMBER() OVER (ORDER BY day DESC) AS rn
      FROM counted_days
     WHERE day <= v_today
  )
  SELECT
    (SELECT day FROM ordered WHERE rn = 1),
    (SELECT MAX(day) FROM training_days WHERE day <= v_today),
    -- Gaps and islands: in a descending list, every day in an unbroken run
    -- from the top satisfies day + (rn - 1) = the top day. The first gap
    -- breaks the equality for everything after it.
    (SELECT COUNT(*) FROM ordered
      WHERE day + (rn - 1)::INT = (SELECT day FROM ordered WHERE rn = 1))
  INTO v_last_counted, v_last_trained, v_streak;

  IF v_last_counted IS NULL OR v_last_counted < v_today - 1 THEN
    v_streak := 0;
  END IF;

  RETURN jsonb_build_object(
    'current_streak',    COALESCE(v_streak, 0),
    'trained_today',     COALESCE(v_last_trained = v_today, FALSE),
    'last_trained_date', v_last_trained,
    'today',             v_today,
    'timezone',          v_tz
  );
END;
$$;


ALTER FUNCTION "public"."compute_streak"("p_user_id" "uuid", "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_dungeon_battle"("p_user_id" "uuid", "p_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_event  public.dungeon_events;
  v_hp     INTEGER;
  v_battle UUID;
  v_run    UUID;
BEGIN
  SELECT * INTO v_event FROM public.dungeon_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND: no Dungeon with that id' USING ERRCODE = 'P0001';
  END IF;
  IF v_event.status <> 'open' OR (v_event.ends_at IS NOT NULL AND v_event.ends_at <= now()) THEN
    RAISE EXCEPTION 'EVENT_CLOSED: this Dungeon is not open' USING ERRCODE = 'P0001';
  END IF;
  IF NOT COALESCE((v_event.config->>'open_to_all')::BOOLEAN, TRUE)
     AND NOT EXISTS (SELECT 1 FROM public.dungeon_event_invites
                      WHERE event_id = p_event_id AND user_id = p_user_id) THEN
    RAISE EXCEPTION 'NOT_INVITED: this Dungeon is invitation only' USING ERRCODE = 'P0001';
  END IF;

  -- One live run per player per event; the partial unique index backs this up.
  IF EXISTS (
    SELECT 1 FROM public.dungeon_runs
     WHERE event_id = p_event_id AND user_id = p_user_id
       AND status IN ('joined', 'ready', 'active', 'disconnected', 'downed')
  ) THEN
    RAISE EXCEPTION 'ALREADY_IN_BATTLE: finish or leave your current run first' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE((value->>'player_hp')::INTEGER, 100) INTO v_hp
    FROM public.game_config WHERE key = 'combat_defaults';

  INSERT INTO public.dungeon_battles (event_id, leader_id, status, seed, boss_hp)
  VALUES (p_event_id, p_user_id, 'forming',
          abs(('x' || substr(md5(random()::TEXT || clock_timestamp()::TEXT), 1, 15))::BIT(60)::BIGINT),
          v_event.boss_max_hp)
  RETURNING id INTO v_battle;

  INSERT INTO public.dungeon_runs (battle_id, event_id, user_id, status, combat_hp, combat_hp_max)
  VALUES (v_battle, p_event_id, p_user_id, 'ready', v_hp, v_hp)
  RETURNING id INTO v_run;

  RETURN jsonb_build_object(
    'success', TRUE, 'battle_id', v_battle, 'run_id', v_run,
    'event_id', p_event_id, 'status', 'forming', 'boss_hp', v_event.boss_max_hp
  );
END;
$$;


ALTER FUNCTION "public"."create_dungeon_battle"("p_user_id" "uuid", "p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_notice_version"("p_consent_type" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT version FROM public.privacy_notices
  WHERE consent_type = p_consent_type
  ORDER BY published_at DESC, version DESC
  LIMIT 1;
$$;


ALTER FUNCTION "public"."current_notice_version"("p_consent_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decide_verification_application"("p_application_id" "uuid", "p_admin_id" "uuid", "p_decision" "text", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_row public.verification_applications%ROWTYPE;
BEGIN
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'INVALID_DECISION: decision must be approved or rejected';
  END IF;
  IF p_decision = 'rejected' AND coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED: give the applicant a reason for the rejection';
  END IF;
  IF EXISTS (SELECT 1 FROM public.verification_applications WHERE id = p_application_id AND user_id = p_admin_id) THEN
    RAISE EXCEPTION 'SELF_REVIEW: another admin has to review your own application';
  END IF;

  UPDATE public.verification_applications
     SET status = p_decision, decided_at = clock_timestamp(), decided_by = p_admin_id,
         decision_reason = nullif(btrim(p_reason), '')
   WHERE id = p_application_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_PENDING: this application is not waiting for review';
  END IF;

  RETURN jsonb_build_object('application_id', v_row.id, 'user_id', v_row.user_id, 'status', v_row.status,
                            'evidence_count', v_row.evidence_count);
END;
$$;


ALTER FUNCTION "public"."decide_verification_application"("p_application_id" "uuid", "p_admin_id" "uuid", "p_decision" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."derive_strength_record"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_metric_type   TEXT;
  v_bodyweight    NUMERIC;
  v_e1rm          NUMERIC;
  v_relative      NUMERIC;
  v_form_verified BOOLEAN;
  -- Above this, e1RM stops being an estimate. A 20-rep set says far more
  -- about endurance than peak strength. Must match MAX_ELIGIBLE_REPS in
  -- src/lib/strengthScore.js.
  c_max_reps      CONSTANT INTEGER := 12;
  -- Must match MIN_VERIFIED_QUALITY in src/lib/strengthScore.js.
  c_min_quality   CONSTANT NUMERIC := 0.7;
BEGIN
  -- Only loaded, rep-counted work can yield a 1RM estimate.
  IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN
    RETURN NEW;
  END IF;

  IF NEW.reps IS NULL OR NEW.reps < 1 OR NEW.reps > c_max_reps THEN
    RETURN NEW;
  END IF;

  SELECT metric_type INTO v_metric_type
    FROM public.exercises WHERE name = NEW.exercise;

  IF COALESCE(v_metric_type, 'reps') <> 'reps' THEN
    RETURN NEW;
  END IF;

  -- Epley, with the single-rep case corrected: a 1-rep set IS the max, and
  -- the raw formula would inflate it by 3.3%.
  IF NEW.reps = 1 THEN
    v_e1rm := ROUND(NEW.weight_kg, 2);
  ELSE
    v_e1rm := ROUND(NEW.weight_kg * (1 + (NEW.reps::NUMERIC / 30)), 2);
  END IF;

  -- Snapshotted, not joined: users.weight_kg changes over time and a
  -- historical record's relative figure must not drift with it. NULL when
  -- unknown, never defaulted — a wrong denominator produces a wrong rank
  -- that looks authoritative.
  SELECT weight_kg INTO v_bodyweight
    FROM public.users WHERE id = NEW.user_id;

  IF v_bodyweight IS NOT NULL AND v_bodyweight > 0 THEN
    v_relative := ROUND(v_e1rm / v_bodyweight, 3);
  ELSE
    v_relative := NULL;
  END IF;

  -- Camera-observed movement above the quality bar. Manual logs are recorded
  -- and ranked, but never carry the badge: nothing observed them.
  -- CHANGED: and only for an exercise that is camera-reward-eligible — the
  -- same boundary rewards use. log_workout_and_progress already refuses
  -- ineligible camera sets; this keeps the invariant true for any other
  -- path that ever writes a camera workout_log.
  v_form_verified := NEW.workout_source = 'camera'
    AND NEW.rep_quality_score IS NOT NULL
    AND NEW.rep_quality_score >= c_min_quality
    AND public.camera_reward_eligible(NEW.exercise);

  INSERT INTO public.strength_records (
    user_id, workout_log_id, exercise, weight_kg, reps,
    e1rm_kg, formula, bodyweight_kg, relative_e1rm,
    workout_source, rep_quality_score, form_verified, achieved_at
  ) VALUES (
    NEW.user_id, NEW.id, NEW.exercise, ROUND(NEW.weight_kg, 2), NEW.reps,
    v_e1rm, 'epley', v_bodyweight, v_relative,
    NEW.workout_source, NEW.rep_quality_score, v_form_verified,
    COALESCE(NEW.logged_at, now())
  );

  RETURN NEW;
EXCEPTION
  -- A strength record is derived data. If deriving it fails, the workout and
  -- its XP must still stand: losing a logged session to a bookkeeping error
  -- in a secondary system would be a far worse outcome than a missing record.
  WHEN OTHERS THEN
    RAISE WARNING 'derive_strength_record failed for workout_log %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."derive_strength_record"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."equip_collectible"("p_user_id" "uuid", "p_collectible_id" "uuid", "p_equipped" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_kind TEXT;
BEGIN
  SELECT c.kind INTO v_kind
    FROM public.user_collectibles uc
    JOIN public.collectibles c ON c.id = uc.collectible_id
   WHERE uc.user_id = p_user_id AND uc.collectible_id = p_collectible_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_OWNED: you do not own that item' USING ERRCODE = 'P0001';
  END IF;

  IF p_equipped THEN
    -- One per kind: equipping a title takes the old title off.
    UPDATE public.user_collectibles uc
       SET equipped = FALSE
      FROM public.collectibles c
     WHERE c.id = uc.collectible_id
       AND uc.user_id = p_user_id
       AND c.kind = v_kind
       AND uc.equipped;
  END IF;

  UPDATE public.user_collectibles
     SET equipped = p_equipped
   WHERE user_id = p_user_id AND collectible_id = p_collectible_id;

  RETURN jsonb_build_object('success', TRUE, 'equipped', p_equipped, 'kind', v_kind);
END;
$$;


ALTER FUNCTION "public"."equip_collectible"("p_user_id" "uuid", "p_collectible_id" "uuid", "p_equipped" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."export_coverage_gaps"() RETURNS SETOF "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT DISTINCT c.relname::text || '.' || a.attname::text
  FROM pg_constraint k
  JOIN pg_class c ON c.oid = k.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  JOIN LATERAL unnest(k.conkey) AS col(attnum) ON TRUE
  JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = col.attnum
  WHERE k.contype = 'f'
    AND k.confrelid IN ('public.users'::regclass, 'auth.users'::regclass)
    AND NOT EXISTS (
      SELECT 1 FROM public.privacy_export_coverage p
      WHERE p.table_name = c.relname::text AND p.column_name = a.attname::text
    );
$$;


ALTER FUNCTION "public"."export_coverage_gaps"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."export_user_data"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_out JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'UNKNOWN_USER: account not found';
  END IF;

  SELECT jsonb_build_object(
    'format', 'gymapp-personal-data-export',
    'format_version', 1,
    'generated_at', now(),
    'notes', jsonb_build_array(
      'This file contains the data linked to your account at the time it was generated.',
      'Camera video is never uploaded, so none is included. GPS routes are kept only on your device, so none are included.',
      'Deliberately excluded (pending privacy review): reports filed about you, moderator review records, and the admin audit log.'
    ),
    'excluded', coalesce((SELECT jsonb_agg(jsonb_build_object('table', table_name, 'column', column_name, 'reason', reason) ORDER BY table_name, column_name)
                          FROM public.privacy_export_coverage WHERE status = 'excluded'), '[]'::jsonb),
    'account', (SELECT jsonb_build_object('email', au.email, 'created_at', au.created_at,
                                          'email_confirmed_at', au.email_confirmed_at, 'last_sign_in_at', au.last_sign_in_at)
                FROM auth.users au WHERE au.id = p_user_id),
    'profile', (SELECT to_jsonb(x) FROM public.users x WHERE x.id = p_user_id),
    'workout_logs', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.logged_at) FROM public.workout_logs x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'strength_records', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.achieved_at) FROM public.strength_records x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'rank_history', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.achieved_at) FROM public.rank_history x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'xp_grants', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.xp_grants x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'specialization_xp', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.focus_type) FROM public.user_specialization_xp x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'meal_logs', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.logged_at) FROM public.fitrack_logs x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'ai_suggestions', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.generated_at) FROM public.ai_suggestions x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'reference_reps', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.exercise) FROM public.user_exercise_templates x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'routines', coalesce((SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object('exercises',
                   coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.position) FROM public.routine_exercises e WHERE e.routine_id = r.id), '[]'::jsonb))
                   ORDER BY r.created_at) FROM public.routines r WHERE r.user_id = p_user_id), '[]'::jsonb),
    'chat_messages', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.chat_messages x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'direct_messages', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.direct_messages x
                                 WHERE x.sender_id = p_user_id OR x.recipient_id = p_user_id), '[]'::jsonb),
    'friendships', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.friendships x
                             WHERE x.requester_id = p_user_id OR x.addressee_id = p_user_id), '[]'::jsonb),
    'community_posts', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.gymmunity_posts x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'reports_filed', coalesce((SELECT jsonb_agg((to_jsonb(x) - 'reviewed_by') ORDER BY x.created_at) FROM public.user_reports x WHERE x.reporter_id = p_user_id), '[]'::jsonb),
    'bug_reports', coalesce((SELECT jsonb_agg((to_jsonb(x) - 'reviewed_by') ORDER BY x.created_at) FROM public.bug_reports x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'gold_ledger', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.gold_ledger x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'shop_purchases', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at) FROM public.shop_purchases x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'inventory', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.item_key) FROM public.user_inventory x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'item_uses', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.used_at) FROM public.item_uses x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'collectibles', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.acquired_at) FROM public.user_collectibles x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'streak_shields', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.covered_date) FROM public.streak_shields x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'mission_attempts', coalesce((SELECT jsonb_agg(to_jsonb(a) || jsonb_build_object('objective_results',
                          coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at) FROM public.mission_objective_results o WHERE o.attempt_id = a.id), '[]'::jsonb))
                          ORDER BY a.started_at) FROM public.mission_attempts a WHERE a.user_id = p_user_id), '[]'::jsonb),
    'mission_clears', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.cleared_at) FROM public.mission_clears x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'dungeon_runs', coalesce((SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object('objective_results',
                      coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at) FROM public.dungeon_objective_results o WHERE o.actor_run_id = r.id), '[]'::jsonb))
                      ORDER BY r.joined_at) FROM public.dungeon_runs r WHERE r.user_id = p_user_id), '[]'::jsonb),
    'dungeon_clears', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.cleared_at) FROM public.dungeon_clears x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'dungeon_invites', coalesce((SELECT jsonb_agg((to_jsonb(x) - 'invited_by') ORDER BY x.created_at) FROM public.dungeon_event_invites x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'food_budget', (SELECT to_jsonb(x) FROM public.user_budget_settings x WHERE x.user_id = p_user_id),
    'entered_prices', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.entered_at) FROM public.user_commodity_prices x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'coach_applications', coalesce((SELECT jsonb_agg((to_jsonb(x) - 'decided_by' - 'revoked_by') ORDER BY x.submitted_at)
                                    FROM public.verification_applications x WHERE x.user_id = p_user_id), '[]'::jsonb),
    'training_survey', (SELECT to_jsonb(x) FROM public.training_surveys x WHERE x.user_id = p_user_id),
    'training_limits', (SELECT to_jsonb(x) FROM public.training_limits x WHERE x.user_id = p_user_id),
    'training_plans', coalesce((SELECT jsonb_agg(to_jsonb(p) || jsonb_build_object(
                         'days', coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.day) FROM public.training_plan_days d WHERE d.plan_id = p.id), '[]'::jsonb),
                         'ratings', coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at) FROM public.training_plan_feedback f WHERE f.plan_id = p.id), '[]'::jsonb))
                       ORDER BY p.created_at) FROM public.training_plans p WHERE p.user_id = p_user_id), '[]'::jsonb),
    'consents', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.acknowledged_at) FROM public.user_consents x WHERE x.user_id = p_user_id), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$$;


ALTER FUNCTION "public"."export_user_data"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."foods_set_search_text"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.search_text := lower(concat_ws(' ', NEW.name, array_to_string(NEW.local_names, ' '), array_to_string(NEW.aliases, ' ')));
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."foods_set_search_text"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_timezone"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(
    (SELECT value->>'timezone' FROM public.game_config WHERE key = 'streak_rules'),
    'Asia/Manila'
  );
$$;


ALTER FUNCTION "public"."game_timezone"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_budget_data"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'budget', (
      SELECT jsonb_build_object('daily_budget_php', b.daily_budget_php, 'updated_at', b.updated_at)
      FROM public.user_budget_settings b WHERE b.user_id = p_user_id
    ),
    'commodities', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', c.slug,
        'name', c.name,
        'local_names', to_jsonb(c.local_names),
        'commodity_group', c.commodity_group,
        'purchase_unit', c.purchase_unit,
        'grams_per_piece', c.grams_per_piece,
        'grams_per_piece_source', c.grams_per_piece_source,
        'inedible_share', c.inedible_share,
        'inedible_share_source', c.inedible_share_source,
        'calculation_note', c.calculation_note,
        'food', CASE WHEN f.id IS NULL THEN NULL ELSE jsonb_build_object(
          'food_id', f.id, 'slug', f.slug, 'name', f.name,
          'calories', f.calories, 'protein', f.protein, 'carbs', f.carbs, 'fat', f.fat,
          'source', f.source, 'source_reference', f.source_reference,
          'is_estimate', f.is_estimate, 'estimate_note', f.estimate_note
        ) END,
        'reference_price', rp.j,
        'user_price', up.j
      ) ORDER BY c.sort_order, c.slug)
      FROM public.market_commodities c
      LEFT JOIN public.foods f ON f.id = c.food_id
      LEFT JOIN LATERAL (
        SELECT jsonb_build_object(
          'id', r.id, 'price_php', r.price_php, 'unit', r.unit, 'region', r.region,
          'period_start', r.period_start, 'period_end', r.period_end,
          'source', r.source, 'source_label', r.source_label, 'source_reference', r.source_reference,
          'source_item', r.source_item, 'specification', r.specification,
          'note', r.note
        ) AS j
        FROM public.commodity_reference_prices r
        WHERE r.commodity_id = c.id
        ORDER BY r.period_end DESC, r.created_at DESC
        LIMIT 1
      ) rp ON TRUE
      LEFT JOIN LATERAL (
        SELECT jsonb_build_object('id', u.id, 'price_php', u.price_php, 'unit', u.unit, 'entered_at', u.entered_at) AS j
        FROM public.user_commodity_prices u
        WHERE u.user_id = p_user_id AND u.commodity_id = c.id
        ORDER BY u.entered_at DESC, u.id DESC
        LIMIT 1
      ) up ON TRUE
      WHERE c.active
    ), '[]'::jsonb)
  );
$$;


ALTER FUNCTION "public"."get_budget_data"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_collection"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_owned JSONB;
BEGIN
  SELECT jsonb_agg(
           jsonb_build_object(
             'collectible_id', c.id, 'key', c.key, 'kind', c.kind, 'name', c.name,
             'description', c.description, 'rarity', c.rarity, 'color', r.color,
             'equipped', uc.equipped, 'acquired_at', uc.acquired_at,
             'source_type', uc.source_type
           ) ORDER BY r.sort_order DESC, uc.acquired_at)
    INTO v_owned
    FROM public.user_collectibles uc
    JOIN public.collectibles c ON c.id = uc.collectible_id
    JOIN public.rarities r ON r.key = c.rarity
   WHERE uc.user_id = p_user_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'owned', COALESCE(v_owned, '[]'::jsonb),
    'total_collectibles', (SELECT COUNT(*) FROM public.collectibles WHERE is_active)
  );
END;
$$;


ALTER FUNCTION "public"."get_collection"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_notices"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT coalesce(jsonb_object_agg(n.consent_type, jsonb_build_object(
    'version', n.version, 'title', n.title, 'body', n.body,
    'is_draft', n.is_draft, 'published_at', n.published_at
  )), '{}'::jsonb)
  FROM (
    SELECT DISTINCT ON (consent_type) *
    FROM public.privacy_notices
    ORDER BY consent_type, published_at DESC, version DESC
  ) n;
$$;


ALTER FUNCTION "public"."get_current_notices"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dungeon_battle_state"("p_user_id" "uuid", "p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle public.dungeon_battles;
  v_event  public.dungeon_events;
  v_run    public.dungeon_runs;
  v_rules  JSONB;
  v_mine   JSONB;
  v_party  JSONB;
  v_help   JSONB;
BEGIN
  SELECT * INTO v_run FROM public.dungeon_runs
   WHERE battle_id = p_battle_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_IN_BATTLE: you are not part of this battle' USING ERRCODE = 'P0001';
  END IF;

  -- Housekeeping BEFORE presence is stamped, so it can judge how long this
  -- player was actually silent — and it is told who is asking, so a party
  -- coming back from an outage recovers on this call rather than the next.
  PERFORM public.settle_dungeon_time(p_battle_id, p_user_id);

  UPDATE public.dungeon_runs
     SET last_seen_at = now(),
         status = CASE WHEN status = 'disconnected' THEN 'active' ELSE status END
   WHERE id = v_run.id;
  UPDATE public.dungeon_battles SET last_activity_at = now() WHERE id = p_battle_id;

  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id;
  SELECT * INTO v_event FROM public.dungeon_events WHERE id = v_battle.event_id;
  SELECT * INTO v_run FROM public.dungeon_runs WHERE id = v_run.id;
  SELECT value INTO v_rules FROM public.game_config WHERE key = 'dungeon_rules';

  SELECT jsonb_build_object(
           'assignment_id', a.id, 'exercise', a.exercise, 'metric_type', e.metric_type,
           'target_value', a.target_value, 'progress', a.progress,
           'remaining', GREATEST(a.target_value - a.progress, 0),
           'base_damage', a.base_damage,
           'difficulty', a.difficulty, 'started_at', a.started_at, 'deadline_at', a.deadline_at
         )
    INTO v_mine
    FROM public.dungeon_assignments a
    JOIN public.exercises e ON e.name = a.exercise
   WHERE a.run_id = v_run.id AND a.status = 'active'
   LIMIT 1;

  SELECT jsonb_agg(
           jsonb_build_object(
             'run_id', r.id, 'user_id', r.user_id, 'username', u.username,
             'status', r.status, 'combat_hp', r.combat_hp, 'combat_hp_max', r.combat_hp_max,
             'total_damage', r.total_damage, 'is_me', r.user_id = p_user_id,
             'exercise', (SELECT a.exercise FROM public.dungeon_assignments a
                           WHERE a.run_id = r.id AND a.status = 'active' LIMIT 1),
             'progress_ratio', (SELECT CASE WHEN a.target_value > 0 THEN ROUND(a.progress / a.target_value, 2) END
                                  FROM public.dungeon_assignments a
                                 WHERE a.run_id = r.id AND a.status = 'active' LIMIT 1)
           ) ORDER BY r.joined_at)
    INTO v_party
    FROM public.dungeon_runs r
    JOIN public.users u ON u.id = r.user_id
   WHERE r.battle_id = p_battle_id;

  -- Teammate objectives this player could pitch in on: started, unfinished,
  -- and theirs rather than ours. Offered only while our own set is not
  -- running, which is the rule the RPC enforces too.
  IF v_mine IS NULL OR (v_mine->>'started_at') IS NULL THEN
    SELECT jsonb_agg(
             jsonb_build_object(
               'assignment_id', a.id, 'run_id', a.run_id, 'username', u.username,
               'exercise', a.exercise, 'metric_type', e.metric_type,
               'target_value', a.target_value, 'progress', a.progress,
               'remaining', GREATEST(a.target_value - a.progress, 0),
               'deadline_at', a.deadline_at
             ) ORDER BY a.deadline_at)
      INTO v_help
      FROM public.dungeon_assignments a
      JOIN public.dungeon_runs r ON r.id = a.run_id
      JOIN public.users u ON u.id = r.user_id
      JOIN public.exercises e ON e.name = a.exercise
     WHERE a.battle_id = p_battle_id
       AND a.status = 'active'
       AND a.started_at IS NOT NULL
       AND a.run_id <> v_run.id
       AND r.status IN ('active', 'disconnected');
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'battle', jsonb_build_object(
      'id', v_battle.id, 'status', v_battle.status, 'boss_hp', v_battle.boss_hp,
      'boss_max_hp', v_event.boss_max_hp, 'leader_id', v_battle.leader_id,
      'is_leader', v_battle.leader_id = p_user_id, 'paused_at', v_battle.paused_at
    ),
    'event', jsonb_build_object(
      'id', v_event.id, 'name', v_event.name, 'threat_rank', v_event.threat_rank,
      'boss_name', (SELECT name FROM public.bosses WHERE id = v_event.boss_id),
      'difficulty', v_event.difficulty, 'ends_at', v_event.ends_at,
      'potions', v_event.config->'potions',
      'min_contribution_percent', v_event.config->'min_contribution_percent',
      'reward_xp', v_event.config->'reward_xp', 'reward_gold', v_event.config->'reward_gold',
      'party_max', COALESCE((v_event.config->>'party_max')::INTEGER, (v_rules->>'party_max')::INTEGER, 4)
    ),
    'me', jsonb_build_object(
      'run_id', v_run.id, 'status', v_run.status, 'combat_hp', v_run.combat_hp,
      'combat_hp_max', v_run.combat_hp_max, 'total_damage', v_run.total_damage,
      'contribution_percent', v_run.contribution_percent, 'reward_eligible', v_run.reward_eligible,
      'bonus_seconds', v_run.bonus_seconds,
      'downed_at', v_run.downed_at,
      'revive_deadline_at', CASE WHEN v_run.status = 'downed' AND v_run.downed_at IS NOT NULL
        THEN v_run.downed_at + make_interval(secs => COALESCE((v_rules->>'revive_window_seconds')::INTEGER, 120))
      END,
      'objective', v_mine
    ),
    'party', COALESCE(v_party, '[]'::jsonb),
    'can_help', COALESCE(v_help, '[]'::jsonb),
    'poll_seconds', COALESCE((v_rules->>'state_poll_seconds')::INTEGER, 3),
    'already_cleared', EXISTS (SELECT 1 FROM public.dungeon_clears
                                WHERE event_id = v_event.id AND user_id = p_user_id)
  );
END;
$$;


ALTER FUNCTION "public"."get_dungeon_battle_state"("p_user_id" "uuid", "p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dungeon_events"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_events JSONB;
  v_live   JSONB;
BEGIN
  UPDATE public.dungeon_events
     SET status = 'closed'
   WHERE status = 'open' AND ends_at IS NOT NULL AND ends_at <= now();

  SELECT jsonb_agg(
           jsonb_build_object(
             'id', e.id, 'name', e.name, 'threat_rank', e.threat_rank,
             'is_anomalous', tr.is_anomalous, 'rank_label', tr.label,
             'boss_name', b.name, 'boss_lore', b.lore, 'boss_max_hp', e.boss_max_hp,
             'difficulty', e.difficulty, 'ends_at', e.ends_at,
             'potions', e.config->'potions',
             'min_contribution_percent', e.config->'min_contribution_percent',
             'reward_xp', e.config->'reward_xp', 'reward_gold', e.config->'reward_gold',
             'recommended_party', tr.properties->'recommended_party',
             'warn_solo', COALESCE((tr.properties->>'warn_solo')::BOOLEAN, FALSE),
             'cleared', dc.user_id IS NOT NULL,
             'cleared_at', dc.cleared_at
           ) ORDER BY tr.sort_order DESC, e.ends_at)
    INTO v_events
    FROM public.dungeon_events e
    JOIN public.threat_ranks tr ON tr.key = e.threat_rank
    LEFT JOIN public.bosses b ON b.id = e.boss_id
    LEFT JOIN public.dungeon_clears dc ON dc.event_id = e.id AND dc.user_id = p_user_id
   WHERE e.status = 'open'
     AND (COALESCE((e.config->>'open_to_all')::BOOLEAN, TRUE)
          OR EXISTS (SELECT 1 FROM public.dungeon_event_invites i
                      WHERE i.event_id = e.id AND i.user_id = p_user_id));

  SELECT jsonb_build_object(
           'battle_id', r.battle_id, 'event_id', r.event_id, 'run_id', r.id,
           'run_status', r.status, 'battle_status', bt.status,
           'event_name', e.name, 'boss_name', b.name
         )
    INTO v_live
    FROM public.dungeon_runs r
    JOIN public.dungeon_battles bt ON bt.id = r.battle_id
    JOIN public.dungeon_events e ON e.id = r.event_id
    LEFT JOIN public.bosses b ON b.id = e.boss_id
   WHERE r.user_id = p_user_id
     AND r.status IN ('joined', 'ready', 'active', 'disconnected', 'downed')
     AND bt.status IN ('forming', 'active', 'paused')
   LIMIT 1;

  RETURN jsonb_build_object(
    'success', TRUE,
    'events', COALESCE(v_events, '[]'::jsonb),
    'live', v_live,
    'cleared_count', (SELECT COUNT(*) FROM public.dungeon_clears WHERE user_id = p_user_id)
  );
END;
$$;


ALTER FUNCTION "public"."get_dungeon_events"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dungeon_leaderboard"("p_user_id" "uuid", "p_scope" "text" DEFAULT 'clears'::"text", "p_limit" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_rows JSONB;
  v_me   JSONB;
  v_lim  INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
BEGIN
  IF p_scope NOT IN ('clears', 'damage') THEN
    RAISE EXCEPTION 'INVALID_SCOPE: scope must be clears or damage' USING ERRCODE = 'P0001';
  END IF;

  WITH stats AS (
    SELECT
      u.id AS user_id,
      u.username,
      u.avatar_url,
      u.focus_type,
      COUNT(DISTINCT dc.event_id) AS clears,
      COALESCE((SELECT SUM(r.total_damage) FROM public.dungeon_runs r WHERE r.user_id = u.id), 0) AS damage,
      (SELECT tr.key
         FROM public.dungeon_clears c2
         JOIN public.dungeon_events e2 ON e2.id = c2.event_id
         JOIN public.threat_ranks tr ON tr.key = e2.threat_rank
        WHERE c2.user_id = u.id
        ORDER BY tr.sort_order DESC
        LIMIT 1) AS best_rank,
      ROUND(AVG(dc.contribution_percent), 1) AS avg_contribution
    FROM public.users u
    JOIN public.dungeon_clears dc ON dc.user_id = u.id
   WHERE u.deactivated_at IS NULL
   GROUP BY u.id, u.username, u.avatar_url, u.focus_type
  ),
  ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
             ORDER BY CASE WHEN p_scope = 'damage' THEN s.damage ELSE s.clears END DESC,
                      CASE WHEN p_scope = 'damage' THEN s.clears ELSE s.damage END DESC,
                      s.username
           ) AS position
      FROM stats s
  )
  SELECT
    jsonb_agg(jsonb_build_object(
      'position', r.position, 'user_id', r.user_id, 'username', r.username,
      'avatar_url', r.avatar_url, 'focus_type', r.focus_type,
      'clears', r.clears, 'damage', r.damage,
      'best_rank', r.best_rank, 'avg_contribution', r.avg_contribution,
      'is_me', r.user_id = p_user_id
    ) ORDER BY r.position) FILTER (WHERE r.position <= v_lim),
    (jsonb_agg(jsonb_build_object(
      'position', r.position, 'username', r.username, 'clears', r.clears,
      'damage', r.damage, 'best_rank', r.best_rank,
      'avg_contribution', r.avg_contribution, 'in_top', r.position <= v_lim
    )) FILTER (WHERE r.user_id = p_user_id)) -> 0
    INTO v_rows, v_me
    FROM ranked r;

  RETURN jsonb_build_object(
    'success', TRUE,
    'scope', p_scope,
    'entries', COALESCE(v_rows, '[]'::jsonb),
    'me', v_me,
    'total_players', (SELECT COUNT(DISTINCT user_id) FROM public.dungeon_clears),
    'total_events', (SELECT COUNT(*) FROM public.dungeon_events WHERE status <> 'draft'),
    'threat_ranks', (SELECT jsonb_object_agg(key, jsonb_build_object('label', label, 'sort', sort_order))
                       FROM public.threat_ranks)
  );
END;
$$;


ALTER FUNCTION "public"."get_dungeon_leaderboard"("p_user_id" "uuid", "p_scope" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_joinable_dungeon_battles"("p_user_id" "uuid", "p_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_rows JSONB;
BEGIN
  SELECT jsonb_agg(
           jsonb_build_object(
             'battle_id', b.id,
             'leader_id', b.leader_id,
             'leader_name', u.username,
             'party_size', (SELECT COUNT(*) FROM public.dungeon_runs r WHERE r.battle_id = b.id),
             'members', (SELECT jsonb_agg(mu.username ORDER BY mr.joined_at)
                           FROM public.dungeon_runs mr
                           JOIN public.users mu ON mu.id = mr.user_id
                          WHERE mr.battle_id = b.id),
             'created_at', b.created_at,
             'eligibility', public.can_join_dungeon_battle(p_user_id, b.id)
           ) ORDER BY b.created_at)
    INTO v_rows
    FROM public.dungeon_battles b
    LEFT JOIN public.users u ON u.id = b.leader_id
   WHERE b.event_id = p_event_id
     AND b.status = 'forming'
     AND b.leader_id IS DISTINCT FROM p_user_id;

  RETURN jsonb_build_object('success', TRUE, 'parties', COALESCE(v_rows, '[]'::jsonb));
END;
$$;


ALTER FUNCTION "public"."get_joinable_dungeon_battles"("p_user_id" "uuid", "p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_mission_board"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_chapters JSONB;
  v_active   JSONB;
BEGIN
  SELECT jsonb_agg(ch ORDER BY ch_number)
    INTO v_chapters
  FROM (
    SELECT c.number AS ch_number,
           jsonb_build_object(
             'id', c.id,
             'number', c.number,
             'name', c.name,
             'missions', COALESCE((
               SELECT jsonb_agg(
                        jsonb_build_object(
                          'id', m.id,
                          'level_number', m.level_number,
                          'name', m.name,
                          'rank', m.rank,
                          'difficulty', m.difficulty,
                          'is_boss_level', m.is_boss_level,
                          'max_hp', m.max_hp,
                          'time_limit_seconds', m.time_limit_seconds,
                          'reward_xp', m.reward_xp,
                          'reward_gold', m.reward_gold,
                          'boss_name', b.name,
                          'boss_lore', b.lore,
                          'objective_count', (SELECT COUNT(*) FROM public.mission_objectives o WHERE o.mission_id = m.id),
                          'objectives', COALESCE((
                            SELECT jsonb_agg(jsonb_build_object(
                                     'sequence', o.sequence,
                                     'exercise', o.exercise,
                                     'metric_type', e.metric_type,
                                     'target_value', o.target_value,
                                     'base_damage', o.base_damage
                                   ) ORDER BY o.sequence)
                              FROM public.mission_objectives o
                              JOIN public.exercises e ON e.name = o.exercise
                             WHERE o.mission_id = m.id), '[]'::jsonb),
                          'cleared', cl.user_id IS NOT NULL,
                          'grade', cl.grade,
                          'cleared_at', cl.cleared_at,
                          -- Level 1 is always open; everything after it needs
                          -- the previous level cleared.
                          'unlocked', m.level_number = 1 OR EXISTS (
                            SELECT 1
                              FROM public.mission_clears pc
                              JOIN public.missions pm ON pm.id = pc.mission_id
                             WHERE pc.user_id = p_user_id
                               AND pm.chapter_id = m.chapter_id
                               AND pm.level_number = m.level_number - 1
                          )
                        ) ORDER BY m.level_number)
                 FROM public.missions m
                 LEFT JOIN public.bosses b ON b.id = m.boss_id
                 LEFT JOIN public.mission_clears cl ON cl.mission_id = m.id AND cl.user_id = p_user_id
                WHERE m.chapter_id = c.id AND m.is_active
             ), '[]'::jsonb)
           ) AS ch
      FROM public.mission_chapters c
     WHERE c.is_active
  ) chapters;

  SELECT jsonb_build_object(
           'attempt_id', a.id,
           'mission_id', a.mission_id,
           'mission_name', m.name,
           'status', a.status,
           'current_sequence', a.current_sequence,
           'boss_hp', a.boss_hp,
           'max_hp', m.max_hp,
           'expires_at', a.expires_at,
           'is_replay', a.is_replay
         )
    INTO v_active
    FROM public.mission_attempts a
    JOIN public.missions m ON m.id = a.mission_id
   WHERE a.user_id = p_user_id AND a.status = 'active' AND a.expires_at > now()
   LIMIT 1;

  RETURN jsonb_build_object(
    'success', TRUE,
    'chapters', COALESCE(v_chapters, '[]'::jsonb),
    'active_attempt', v_active,
    'cleared_count', (SELECT COUNT(*) FROM public.mission_clears WHERE user_id = p_user_id)
  );
END;
$$;


ALTER FUNCTION "public"."get_mission_board"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_verification"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'training_history', public.training_history_counts(p_user_id),
    'coach_block', public.coach_application_block(p_user_id),
    'applications', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'status', a.status, 'submitted_at', a.submitted_at, 'evidence_count', a.evidence_count,
        'decided_at', a.decided_at, 'decision_reason', a.decision_reason, 'withdrawn_at', a.withdrawn_at,
        'revoked_at', a.revoked_at, 'revoked_by_self', a.revoked_by_self, 'revoke_reason', a.revoke_reason,
        'files_deleted', a.files_deleted_at IS NOT NULL
      ) ORDER BY a.submitted_at DESC)
      FROM public.verification_applications a WHERE a.user_id = p_user_id AND a.kind = 'coach'
    ), '[]'::jsonb)
  );
$$;


ALTER FUNCTION "public"."get_my_verification"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_privacy_status"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'notices', public.get_current_notices(),
    'latest', coalesce((
      SELECT jsonb_object_agg(l.consent_type, jsonb_build_object(
        'notice_version', l.notice_version, 'decision', l.decision, 'acknowledged_at', l.acknowledged_at,
        'is_current', l.notice_version = public.current_notice_version(l.consent_type)
      ))
      FROM (
        SELECT DISTINCT ON (consent_type) consent_type, notice_version, decision, acknowledged_at
        FROM public.user_consents
        WHERE user_id = p_user_id
        ORDER BY consent_type, acknowledged_at DESC, id DESC
      ) l
    ), '{}'::jsonb),
    'history', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'consent_type', c.consent_type, 'notice_version', c.notice_version,
        'decision', c.decision, 'acknowledged_at', c.acknowledged_at
      ) ORDER BY c.acknowledged_at DESC)
      FROM public.user_consents c WHERE c.user_id = p_user_id
    ), '[]'::jsonb),
    'relative_leaderboard_opt_in', (SELECT u.relative_leaderboard_opt_in FROM public.users u WHERE u.id = p_user_id)
  );
$$;


ALTER FUNCTION "public"."get_privacy_status"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_public_verification"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'training_history', public.training_history_counts(p_user_id),
    'coach_verified_at', (SELECT decided_at FROM public.verification_applications
                          WHERE user_id = p_user_id AND kind = 'coach' AND status = 'approved')
  );
$$;


ALTER FUNCTION "public"."get_public_verification"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_shop"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_items JSONB;
BEGIN
  SELECT jsonb_agg(
           jsonb_build_object(
             'key', i.key,
             'kind', i.kind,
             'name', i.name,
             'description', i.description,
             'price_gold', i.price_gold,
             'max_stack', i.max_stack,
             'scope', i.scope,
             'effect', i.effect,
             'purchase_cooldown_seconds', i.purchase_cooldown_seconds,
             'use_cooldown_seconds', i.use_cooldown_seconds,
             'owned', COALESCE(inv.quantity, 0),
             'purchase_available_at',
               CASE
                 WHEN i.purchase_cooldown_seconds > 0
                  AND lp.last_at IS NOT NULL
                  AND lp.last_at + make_interval(secs => i.purchase_cooldown_seconds) > now()
                 THEN lp.last_at + make_interval(secs => i.purchase_cooldown_seconds)
               END
           ) ORDER BY i.sort_order)
    INTO v_items
    FROM public.shop_items i
    LEFT JOIN public.user_inventory inv
           ON inv.user_id = p_user_id AND inv.item_key = i.key
    LEFT JOIN LATERAL (
      SELECT MAX(sp.created_at) AS last_at
        FROM public.shop_purchases sp
       WHERE sp.user_id = p_user_id AND sp.item_key = i.key
    ) lp ON TRUE
   WHERE i.is_active;

  RETURN jsonb_build_object(
    'success', TRUE,
    'balance', public.gold_balance(p_user_id),
    'items', COALESCE(v_items, '[]'::jsonb),
    'streak', public.compute_streak(p_user_id),
    'restorable_date', public.streak_restore_candidate(p_user_id)
  );
END;
$$;


ALTER FUNCTION "public"."get_shop"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gold_balance"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(SUM(amount), 0)::INTEGER
    FROM public.gold_ledger
   WHERE user_id = p_user_id;
$$;


ALTER FUNCTION "public"."gold_balance"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."grant_bonus_xp"("p_user_id" "uuid", "p_amount" integer, "p_source_type" "text", "p_source_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_id     UUID;
  v_result JSONB;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_XP: a bonus grant must be positive, got %', p_amount
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.xp_grants (user_id, amount, source_type, source_id)
  VALUES (p_user_id, p_amount, p_source_type, p_source_id)
  ON CONFLICT (user_id, source_type, source_id) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('granted', FALSE, 'duplicate', TRUE, 'amount', 0);
  END IF;

  v_result := public.apply_xp_gain(p_user_id, p_amount);

  UPDATE public.xp_grants
     SET focus_type = v_result->>'focus_type'
   WHERE id = v_id;

  RETURN jsonb_build_object('granted', TRUE, 'duplicate', FALSE, 'amount', p_amount, 'grant_id', v_id)
         || v_result;
END;
$$;


ALTER FUNCTION "public"."grant_bonus_xp"("p_user_id" "uuid", "p_amount" integer, "p_source_type" "text", "p_source_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_user_consents"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id) THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'RECORD_IMMUTABLE: consent records are kept as written; record a new decision instead';
END;
$$;


ALTER FUNCTION "public"."guard_user_consents"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_verification_applications"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Only the account-deletion cascade may remove an application record.
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'RECORD_IMMUTABLE: verification records are kept; they are not deleted';
  END IF;

  IF (NEW.id, NEW.user_id, NEW.kind, NEW.experience_summary, NEW.evidence_count, NEW.evidence_hashes,
      NEW.evidence_sizes, NEW.notice_version, NEW.submitted_at)
     IS DISTINCT FROM
     (OLD.id, OLD.user_id, OLD.kind, OLD.experience_summary, OLD.evidence_count, OLD.evidence_hashes,
      OLD.evidence_sizes, OLD.notice_version, OLD.submitted_at) THEN
    RAISE EXCEPTION 'RECORD_IMMUTABLE: submitted application details cannot change';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected', 'withdrawn'))
    OR (OLD.status = 'approved' AND NEW.status = 'revoked')
  ) THEN
    RAISE EXCEPTION 'INVALID_TRANSITION: % cannot become %', OLD.status, NEW.status;
  END IF;

  -- Once written, decision, withdrawal, revocation and deletion facts stay.
  IF (OLD.decided_at IS NOT NULL AND (NEW.decided_at, NEW.decided_by, NEW.decision_reason)
        IS DISTINCT FROM (OLD.decided_at, OLD.decided_by, OLD.decision_reason))
  OR (OLD.withdrawn_at IS NOT NULL AND NEW.withdrawn_at IS DISTINCT FROM OLD.withdrawn_at)
  OR (OLD.revoked_at IS NOT NULL AND (NEW.revoked_at, NEW.revoked_by, NEW.revoked_by_self, NEW.revoke_reason)
        IS DISTINCT FROM (OLD.revoked_at, OLD.revoked_by, OLD.revoked_by_self, OLD.revoke_reason))
  OR (OLD.files_deleted_at IS NOT NULL AND NEW.files_deleted_at IS DISTINCT FROM OLD.files_deleted_at) THEN
    RAISE EXCEPTION 'RECORD_IMMUTABLE: recorded decisions cannot be rewritten';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_verification_applications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_current_consent"("p_user_id" "uuid", "p_consent_type" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT coalesce((
    SELECT c.notice_version = public.current_notice_version(p_consent_type)
       AND c.decision IN ('acknowledged', 'granted')
    FROM public.user_consents c
    WHERE c.user_id = p_user_id AND c.consent_type = p_consent_type
    ORDER BY c.acknowledged_at DESC, c.id DESC
    LIMIT 1
  ), FALSE);
$$;


ALTER FUNCTION "public"."has_current_consent"("p_user_id" "uuid", "p_consent_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle public.dungeon_battles;
  v_check  JSONB;
  v_hp     INTEGER;
  v_run    UUID;
BEGIN
  -- Lock the battle first: the party cap and the "already started" rule are
  -- both races otherwise, with two people joining the last slot at once.
  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATTLE_NOT_FOUND: that party no longer exists' USING ERRCODE = 'P0001';
  END IF;

  v_check := public.can_join_dungeon_battle(p_user_id, p_battle_id);
  IF NOT (v_check->>'ok')::BOOLEAN THEN
    RAISE EXCEPTION '%: %', v_check->>'code', v_check->>'reason' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE((value->>'player_hp')::INTEGER, 100) INTO v_hp
    FROM public.game_config WHERE key = 'combat_defaults';

  INSERT INTO public.dungeon_runs (battle_id, event_id, user_id, status, combat_hp, combat_hp_max)
  VALUES (p_battle_id, v_battle.event_id, p_user_id, 'ready', v_hp, v_hp)
  RETURNING id INTO v_run;

  UPDATE public.dungeon_battles SET last_activity_at = now() WHERE id = p_battle_id;

  RETURN jsonb_build_object(
    'success', TRUE, 'battle_id', p_battle_id, 'run_id', v_run,
    'event_id', v_battle.event_id, 'status', 'forming'
  );
END;
$$;


ALTER FUNCTION "public"."join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_admin_audit_log"("p_limit" integer, "p_before" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'actor_user_id', a.actor_user_id, 'actor_username', u.username, 'actor_role', a.actor_role,
    'action', a.action, 'target_type', a.target_type, 'target_id', a.target_id,
    'metadata', a.metadata, 'created_at', a.created_at
  ) ORDER BY a.created_at DESC), '[]'::jsonb)
  FROM (
    SELECT * FROM public.admin_audit_log
    WHERE p_before IS NULL OR created_at < p_before
    ORDER BY created_at DESC
    LIMIT least(greatest(coalesce(p_limit, 50), 1), 200)
  ) a
  LEFT JOIN public.users u ON u.id = a.actor_user_id;
$$;


ALTER FUNCTION "public"."list_admin_audit_log"("p_limit" integer, "p_before" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_meal_entry"("p_user_id" "uuid", "p_logged_method" "text", "p_food_name" "text", "p_weight_g" numeric, "p_calories" numeric, "p_protein" numeric, "p_carbs" numeric, "p_fat" numeric, "p_fiber" numeric, "p_sugar" numeric, "p_meal_period" "text", "p_image_url" "text" DEFAULT NULL::"text", "p_food_id" "uuid" DEFAULT NULL::"uuid", "p_serving_label" "text" DEFAULT NULL::"text", "p_usda" "jsonb" DEFAULT NULL::"jsonb", "p_usda_fdc_claimed" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_food      public.foods%ROWTYPE;
  v_per100    JSONB;
  v_expected  JSONB;
  v_matches   BOOLEAN := FALSE;
  v_source    TEXT := 'user_entered';
  v_estimate  BOOLEAN := NULL;
  v_snapshot  JSONB;
  v_row       public.fitrack_logs%ROWTYPE;
  v_scale     NUMERIC;
  v_key       TEXT;
  v_exp       NUMERIC;
  v_got       NUMERIC;
BEGIN
  IF p_food_id IS NOT NULL AND (p_usda IS NOT NULL OR p_usda_fdc_claimed IS NOT NULL) THEN
    RAISE EXCEPTION 'INVALID_SOURCE: a meal can reference a local food or a USDA record, not both'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_food_id IS NOT NULL THEN
    SELECT * INTO v_food FROM public.foods WHERE id = p_food_id AND active;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'UNKNOWN_FOOD: no active food %', p_food_id USING ERRCODE = 'P0001';
    END IF;
    v_per100 := jsonb_build_object('calories', v_food.calories, 'protein', v_food.protein, 'carbs', v_food.carbs,
                                   'fat', v_food.fat, 'fiber', v_food.fiber, 'sugar', v_food.sugar);
  ELSIF p_usda IS NOT NULL THEN
    v_per100 := p_usda->'per_100g';
  END IF;

  IF v_per100 IS NOT NULL THEN
    v_scale := p_weight_g / 100.0;
    v_expected := '{}'::jsonb;
    v_matches := TRUE;
    FOREACH v_key IN ARRAY ARRAY['calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar'] LOOP
      IF v_per100->>v_key IS NULL THEN
        CONTINUE;  -- unknown in the record: can't be compared, doesn't disqualify
      END IF;
      v_exp := round((v_per100->>v_key)::NUMERIC * v_scale, 1);
      v_expected := v_expected || jsonb_build_object(v_key, v_exp);
      v_got := CASE v_key
        WHEN 'calories' THEN p_calories WHEN 'protein' THEN p_protein WHEN 'carbs' THEN p_carbs
        WHEN 'fat' THEN p_fat WHEN 'fiber' THEN p_fiber ELSE p_sugar END;
      -- Tolerance covers the client's rounding to 0.1 and nothing more.
      IF abs(coalesce(v_got, 0) - v_exp) > greatest(1.0, v_exp * 0.02) THEN
        v_matches := FALSE;
      END IF;
    END LOOP;

    IF p_food_id IS NOT NULL THEN
      v_source := CASE WHEN v_matches THEN 'local_food' ELSE 'user_edited' END;
      v_estimate := CASE WHEN v_matches THEN v_food.is_estimate ELSE NULL END;
    ELSE
      v_source := CASE WHEN v_matches THEN 'usda' ELSE 'user_edited' END;
      v_estimate := CASE WHEN v_matches THEN FALSE ELSE NULL END;
    END IF;
  END IF;

  v_snapshot := jsonb_build_object(
    'captured_at', now(),
    'nutrition_source', v_source,
    'values_match_record', CASE WHEN v_per100 IS NULL THEN NULL ELSE v_matches END,
    'weight_g', p_weight_g,
    'serving_label', p_serving_label,
    'expected_from_record', v_expected,
    'food', CASE WHEN p_food_id IS NULL THEN NULL ELSE jsonb_build_object(
      'food_id', v_food.id, 'slug', v_food.slug, 'name', v_food.name,
      'local_names', to_jsonb(v_food.local_names), 'category', v_food.category,
      'preparation', v_food.preparation, 'nutrition_per_100g', v_per100,
      'source', v_food.source, 'source_reference', v_food.source_reference,
      'is_estimate', v_food.is_estimate, 'estimate_note', v_food.estimate_note) END,
    'usda', CASE WHEN p_usda IS NULL THEN NULL ELSE p_usda || jsonb_build_object('verified_server_side', TRUE) END,
    'usda_claim_unverified', CASE WHEN p_usda IS NULL AND p_usda_fdc_claimed IS NOT NULL THEN p_usda_fdc_claimed ELSE NULL END
  );

  INSERT INTO public.fitrack_logs (
    user_id, logged_method, image_url, food_name, weight_g,
    calories, protein, carbs, fat, fiber, sugar, meal_period,
    food_id, usda_fdc_id, nutrition_source, is_estimate, nutrition_snapshot
  ) VALUES (
    p_user_id, p_logged_method, p_image_url, p_food_name, p_weight_g,
    p_calories, p_protein, p_carbs, p_fat, coalesce(p_fiber, 0), coalesce(p_sugar, 0), p_meal_period,
    p_food_id, CASE WHEN p_usda IS NULL THEN NULL ELSE (p_usda->>'fdc_id')::INTEGER END,
    v_source, v_estimate, v_snapshot
  )
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$$;


ALTER FUNCTION "public"."log_meal_entry"("p_user_id" "uuid", "p_logged_method" "text", "p_food_name" "text", "p_weight_g" numeric, "p_calories" numeric, "p_protein" numeric, "p_carbs" numeric, "p_fat" numeric, "p_fiber" numeric, "p_sugar" numeric, "p_meal_period" "text", "p_image_url" "text", "p_food_id" "uuid", "p_serving_label" "text", "p_usda" "jsonb", "p_usda_fdc_claimed" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_workout_and_progress"("p_user_id" "uuid", "p_exercise" "text", "p_sets" integer, "p_reps" integer, "p_rep_quality_score" numeric, "p_workout_source" "text", "p_weight_kg" numeric DEFAULT NULL::numeric, "p_duration_seconds" integer DEFAULT NULL::integer, "p_distance_m" numeric DEFAULT NULL::numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
DECLARE
  v_reps_multiplier    NUMERIC(4,2);
  v_quality_bonus_max  NUMERIC(4,2);
  v_duration_multiplier NUMERIC(6,2);
  v_distance_multiplier NUMERIC(6,2);

  v_base_xp            INTEGER;
  v_quality_multiplier NUMERIC(4,2);
  v_affinity           NUMERIC(4,2);
  v_xp_earned          INTEGER;

  v_focus_type         TEXT;
  v_xp_result          JSONB;

  v_primary_attribute   TEXT;
  v_attribute_points    INTEGER := 0;

  v_metric_type        TEXT;
  v_sets               INTEGER;
  v_log_id             UUID;

  v_weight_kg           NUMERIC;
  v_volume_scale        CONSTANT NUMERIC := 16.0;
  v_max_weight_kg       CONSTANT NUMERIC := 500;

  v_allowed_sources    TEXT[] := ARRAY['camera', 'manual'];
  v_max_sets           INT    := 20;
  v_max_reps           INT    := 300;
  v_max_duration       INT    := 21600;
  v_max_distance       NUMERIC := 200000;
BEGIN

  -- 1. Input validation
  IF p_workout_source IS NULL OR NOT (p_workout_source = ANY(v_allowed_sources)) THEN
    RAISE EXCEPTION 'INVALID_SOURCE: workout_source must be one of: camera, manual'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT primary_attribute, metric_type
    INTO v_primary_attribute, v_metric_type
    FROM public.exercises WHERE name = p_exercise;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_EXERCISE: exercise "%" is not recognised', p_exercise
      USING ERRCODE = 'P0001';
  END IF;

  -- CHANGED (a): the server, not the client, decides whether a camera set may
  -- produce anything at all.
  IF p_workout_source = 'camera' AND NOT public.camera_reward_eligible(p_exercise) THEN
    RAISE EXCEPTION 'CAMERA_NOT_VALIDATED: "%" has no validated, authorised and XP-configured camera tracker', p_exercise
      USING ERRCODE = 'P0001';
  END IF;

  v_metric_type := COALESCE(v_metric_type, 'reps');

  v_sets := COALESCE(p_sets, 1);
  IF v_sets < 1 OR v_sets > v_max_sets THEN
    RAISE EXCEPTION 'INVALID_SETS: sets must be between 1 and %', v_max_sets
      USING ERRCODE = 'P0001';
  END IF;

  IF v_metric_type = 'reps' THEN
    IF p_reps IS NULL OR p_reps < 1 OR p_reps > v_max_reps THEN
      RAISE EXCEPTION 'INVALID_REPS: reps must be between 1 and %', v_max_reps
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    IF p_duration_seconds IS NULL OR p_duration_seconds < 1 OR p_duration_seconds > v_max_duration THEN
      RAISE EXCEPTION 'INVALID_DURATION: duration_seconds must be between 1 and %', v_max_duration
        USING ERRCODE = 'P0001';
    END IF;
    IF v_metric_type = 'distance' THEN
      IF p_distance_m IS NULL OR p_distance_m < 0 OR p_distance_m > v_max_distance THEN
        RAISE EXCEPTION 'INVALID_DISTANCE: distance_m must be between 0 and %', v_max_distance
          USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  IF p_weight_kg IS NOT NULL AND (p_weight_kg < 0 OR p_weight_kg > v_max_weight_kg) THEN
    RAISE EXCEPTION 'INVALID_WEIGHT: weight_kg must be between 0 and %', v_max_weight_kg
      USING ERRCODE = 'P0001';
  END IF;
  v_weight_kg := NULLIF(p_weight_kg, 0);

  IF p_workout_source = 'camera' AND v_metric_type = 'reps' THEN
    IF p_rep_quality_score IS NULL
       OR p_rep_quality_score < 0.0
       OR p_rep_quality_score > 1.0
    THEN
      RAISE EXCEPTION 'INVALID_QUALITY_SCORE: rep_quality_score must be between 0.0 and 1.0 for camera workouts'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- 2. Lock user row. The focus_type read here feeds the affinity lookup
  -- below, so it has to happen before the XP maths.
  SELECT focus_type
    INTO v_focus_type
    FROM public.users
   WHERE id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: no user with id %', p_user_id
      USING ERRCODE = 'P0002';
  END IF;

  -- 3. XP config lookup
  IF p_workout_source = 'camera' THEN
    -- CHANGED (b): the exercise's own camera row, and nothing else. Eligibility
    -- above already required it to exist; this refuses rather than inventing
    -- a rate if the two ever disagree.
    SELECT reps_multiplier, quality_bonus_max, duration_multiplier, distance_multiplier
      INTO v_reps_multiplier, v_quality_bonus_max, v_duration_multiplier, v_distance_multiplier
      FROM public.xp_config
     WHERE workout_source = 'camera'
       AND exercise_name = p_exercise;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'CAMERA_XP_NOT_CONFIGURED: "%" has no camera xp_config row', p_exercise
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    SELECT reps_multiplier, quality_bonus_max, duration_multiplier, distance_multiplier
      INTO v_reps_multiplier, v_quality_bonus_max, v_duration_multiplier, v_distance_multiplier
      FROM public.xp_config
      WHERE workout_source = p_workout_source
        AND exercise_name = COALESCE(
              (SELECT exercise_name
                 FROM public.xp_config
                WHERE workout_source = p_workout_source
                  AND exercise_name = p_exercise
                LIMIT 1),
              '*'
            )
      LIMIT 1;

    IF v_reps_multiplier IS NULL THEN
      v_reps_multiplier   := 2.0;
      v_quality_bonus_max := 0.0;
    END IF;
  END IF;
  v_duration_multiplier := COALESCE(v_duration_multiplier, 3.0);
  v_distance_multiplier := COALESCE(v_distance_multiplier, 30.0);

  -- 4. XP calculation
  IF v_metric_type = 'duration' THEN
    v_base_xp := ROUND((p_duration_seconds / 60.0) * v_duration_multiplier);

  ELSIF v_metric_type = 'distance' THEN
    v_base_xp := ROUND(
      (p_distance_m / 1000.0) * v_distance_multiplier
      + (p_duration_seconds / 60.0) * v_duration_multiplier
    );

  ELSIF v_weight_kg IS NOT NULL THEN
    v_base_xp := ROUND((v_weight_kg * p_reps) * (v_reps_multiplier / v_volume_scale));

  ELSE
    v_base_xp := ROUND(p_reps * v_reps_multiplier);
  END IF;

  IF p_workout_source = 'camera' AND v_metric_type = 'reps' AND p_rep_quality_score IS NOT NULL THEN
    v_quality_multiplier :=
      ROUND((1.0 + (p_rep_quality_score * v_quality_bonus_max))::NUMERIC, 2);
  ELSE
    v_quality_multiplier := 1.0;
  END IF;

  -- 4b. Specialization affinity. This is what makes a specialization
  -- mechanical rather than cosmetic: a powerlifter's squat and a
  -- calisthenics athlete's pull-up are each worth more on their own path.
  -- 'hybrid' has no affinity rows and therefore always resolves to 1.0.
  v_affinity := public.resolve_specialization_affinity(
    v_focus_type, p_exercise, v_primary_attribute
  );

  v_xp_earned := ROUND(v_base_xp * v_quality_multiplier * v_affinity);

  -- 5. Insert workout log
  INSERT INTO public.workout_logs (
    user_id, exercise, sets, reps, rep_quality_score,
    base_xp, quality_multiplier, xp_earned, workout_source,
    weight_kg, duration_seconds, distance_m
  ) VALUES (
    p_user_id, p_exercise, v_sets, p_reps, COALESCE(p_rep_quality_score, 1.0),
    v_base_xp, v_quality_multiplier, v_xp_earned, p_workout_source,
    v_weight_kg, p_duration_seconds, p_distance_m
  )
  RETURNING id INTO v_log_id;

  -- 6/7. XP, per-path XP, rank and rank history — one shared path now, so
  -- mission and dungeon rewards cannot drift from workout rewards.
  v_xp_result := public.apply_xp_gain(p_user_id, v_xp_earned);

  IF v_primary_attribute IS NOT NULL THEN
    v_attribute_points := v_xp_earned;
    EXECUTE format('UPDATE public.users SET %I = %I + $1 WHERE id = $2', v_primary_attribute, v_primary_attribute)
      USING v_attribute_points, p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'success',           TRUE,
    'workout_log_id',    v_log_id,
    'metric_type',       v_metric_type,
    'xp_earned',         v_xp_earned,
    'base_xp',           v_base_xp,
    'quality_multiplier', v_quality_multiplier,
    'affinity_multiplier', v_affinity,
    'attribute_gained',   v_primary_attribute,
    'attribute_points_earned', v_attribute_points,
    'weight_kg',         v_weight_kg,
    'duration_seconds',  p_duration_seconds,
    'distance_m',        p_distance_m
  ) || v_xp_result;

EXCEPTION
  WHEN SQLSTATE 'P0001' THEN RAISE;
  WHEN SQLSTATE 'P0002' THEN RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'INTERNAL_ERROR: %', SQLERRM
      USING ERRCODE = 'P0003';

END;
$_$;


ALTER FUNCTION "public"."log_workout_and_progress"("p_user_id" "uuid", "p_exercise" "text", "p_sets" integer, "p_reps" integer, "p_rep_quality_score" numeric, "p_workout_source" "text", "p_weight_kg" numeric, "p_duration_seconds" integer, "p_distance_m" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_verification_files_deleted"("p_application_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  UPDATE public.verification_applications
     SET files_deleted_at = clock_timestamp()
   WHERE id = p_application_id AND status <> 'pending' AND files_deleted_at IS NULL;
  RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."mark_verification_files_deleted"("p_application_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mission_damage"("p_base_damage" integer, "p_quality" numeric) RETURNS TABLE("damage" integer, "is_crit" boolean)
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_cfg   JSONB;
  v_min   NUMERIC;
  v_max   NUMERIC;
  v_floor NUMERIC;
  v_crit_at NUMERIC;
  v_crit_mult NUMERIC;
  v_scaled  NUMERIC;
  v_mult    NUMERIC;
BEGIN
  SELECT value INTO v_cfg FROM public.game_config WHERE key = 'form_damage';
  v_min       := COALESCE((v_cfg->>'min_multiplier')::NUMERIC, 1.0);
  v_max       := COALESCE((v_cfg->>'max_multiplier')::NUMERIC, 1.5);
  v_floor     := COALESCE((v_cfg->>'quality_floor')::NUMERIC, 0.5);
  v_crit_at   := COALESCE((v_cfg->>'crit_threshold')::NUMERIC, 0.95);
  v_crit_mult := COALESCE((v_cfg->>'crit_multiplier')::NUMERIC, 1.5);

  IF p_quality IS NULL THEN
    -- Manual entry has no form score, so it earns the floor multiplier and
    -- never crits. Camera work is what the bonus is for.
    RETURN QUERY SELECT ROUND(p_base_damage * v_min)::INTEGER, FALSE;
    RETURN;
  END IF;

  v_scaled := LEAST(GREATEST((p_quality - v_floor) / NULLIF(1.0 - v_floor, 0), 0), 1);
  v_mult   := v_min + (v_max - v_min) * COALESCE(v_scaled, 0);

  IF p_quality >= v_crit_at THEN
    RETURN QUERY SELECT ROUND(p_base_damage * v_mult * v_crit_mult)::INTEGER, TRUE;
  ELSE
    RETURN QUERY SELECT ROUND(p_base_damage * v_mult)::INTEGER, FALSE;
  END IF;
END;
$$;


ALTER FUNCTION "public"."mission_damage"("p_base_damage" integer, "p_quality" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."missions_validate_publish"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NEW.is_active THEN
    PERFORM public.assert_mission_is_clearable(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."missions_validate_publish"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pick_dungeon_exercise"("p_battle_id" "uuid", "p_run_id" "uuid", "p_ordinal" integer) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_cfg        JSONB;
  v_trackable  TEXT[];
  v_fallback   TEXT[];
  v_focus      TEXT;
  v_seed       BIGINT;
  v_avoid_last INTEGER;
  v_pool       TEXT[];
  v_recent     TEXT[];
  v_active     TEXT[];
  v_pick       TEXT;
BEGIN
  SELECT value INTO v_cfg FROM public.game_config WHERE key = 'dungeon_objectives';
  v_avoid_last := COALESCE((v_cfg->>'avoid_last')::INTEGER, 2);
  -- CHANGED: authorised AND validated AND XP-configured, not just listed.
  v_trackable := public.camera_reward_eligible_exercises();
  -- CHANGED: the fallback can only offer what is eligible.
  SELECT ARRAY(SELECT x FROM jsonb_array_elements_text(v_cfg->'fallback') x
                WHERE x = ANY (v_trackable)) INTO v_fallback;

  SELECT u.focus_type, b.seed
    INTO v_focus, v_seed
    FROM public.dungeon_runs r
    JOIN public.users u ON u.id = r.user_id
    JOIN public.dungeon_battles b ON b.id = r.battle_id
   WHERE r.id = p_run_id;

  -- Exercises already being worked on in this battle, and the ones this run
  -- has just done.
  SELECT ARRAY(SELECT exercise FROM public.dungeon_assignments
                WHERE battle_id = p_battle_id AND status = 'active')
    INTO v_active;
  SELECT ARRAY(SELECT exercise FROM public.dungeon_assignments
                WHERE run_id = p_run_id ORDER BY assigned_at DESC LIMIT v_avoid_last)
    INTO v_recent;

  -- The path's own exercises, narrowed to what a camera can watch.
  SELECT ARRAY(
    SELECT a.match_value
      FROM public.specialization_affinity a
     WHERE a.focus_type = v_focus
       AND a.match_type = 'exercise'
       AND a.multiplier > 1
       AND a.match_value = ANY (v_trackable)
  ) INTO v_pool;

  v_pool := ARRAY(SELECT x FROM unnest(v_pool) x
                   WHERE NOT (x = ANY (v_active)) AND NOT (x = ANY (v_recent)));

  IF array_length(v_pool, 1) IS NULL THEN
    v_pool := ARRAY(SELECT x FROM unnest(v_fallback) x
                     WHERE NOT (x = ANY (v_active)) AND NOT (x = ANY (v_recent)));
  END IF;
  IF array_length(v_pool, 1) IS NULL THEN
    v_pool := ARRAY(SELECT x FROM unnest(v_trackable) x WHERE NOT (x = ANY (v_active)));
  END IF;
  IF array_length(v_pool, 1) IS NULL THEN
    RETURN NULL;  -- every trackable exercise is taken; caller waits
  END IF;

  -- Deterministic from the battle seed, so the encounter cannot be rerolled.
  -- abs(): a bit-string cast can come back negative, and a negative index
  -- would silently return NULL instead of an exercise.
  v_pick := v_pool[1 + (
    abs(('x' || substr(md5(v_seed::TEXT || ':' || p_run_id::TEXT || ':' || p_ordinal::TEXT), 1, 8))::BIT(32)::BIGINT)
    % array_length(v_pool, 1)
  )];

  RETURN v_pick;
END;
$$;


ALTER FUNCTION "public"."pick_dungeon_exercise"("p_battle_id" "uuid", "p_run_id" "uuid", "p_ordinal" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ping_dungeon_progress"("p_user_id" "uuid", "p_battle_id" "uuid", "p_progress" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_run UUID;
BEGIN
  SELECT id INTO v_run FROM public.dungeon_runs
   WHERE battle_id = p_battle_id AND user_id = p_user_id
     AND status IN ('active', 'disconnected');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE);
  END IF;

  -- Presence too: a ping proves the player is there just as a poll does.
  UPDATE public.dungeon_runs
     SET last_seen_at = now(), status = CASE WHEN status = 'disconnected' THEN 'active' ELSE status END
   WHERE id = v_run;

  -- GREATEST, so a ping can never walk progress backwards, and capped at the
  -- target so a wild claim cannot render a bar past full.
  UPDATE public.dungeon_assignments
     SET progress = LEAST(GREATEST(progress, GREATEST(p_progress, 0)), target_value)
   WHERE run_id = v_run AND status = 'active' AND started_at IS NOT NULL;

  RETURN jsonb_build_object('success', TRUE);
END;
$$;


ALTER FUNCTION "public"."ping_dungeon_progress"("p_user_id" "uuid", "p_battle_id" "uuid", "p_progress" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."purchase_item"("p_user_id" "uuid", "p_item_key" "text", "p_quantity" integer, "p_request_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_item   public.shop_items;
  v_owned  INTEGER;
  v_last   TIMESTAMPTZ;
  v_spend  JSONB;
  v_wait   INTEGER;
BEGIN
  IF p_request_id IS NULL OR length(p_request_id) < 8 THEN
    RAISE EXCEPTION 'INVALID_REQUEST: a purchase needs a request id' USING ERRCODE = 'P0001';
  END IF;

  -- A retried request answers with the outcome it already had.
  IF EXISTS (SELECT 1 FROM public.shop_purchases WHERE request_id = p_request_id AND user_id = p_user_id) THEN
    RETURN jsonb_build_object(
      'success', TRUE, 'duplicate', TRUE, 'item_key', p_item_key,
      'quantity_owned', COALESCE((SELECT quantity FROM public.user_inventory
                                   WHERE user_id = p_user_id AND item_key = p_item_key), 0),
      'balance', public.gold_balance(p_user_id)
    );
  END IF;

  SELECT * INTO v_item FROM public.shop_items WHERE key = p_item_key AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ITEM_NOT_FOUND: that item is not for sale' USING ERRCODE = 'P0001';
  END IF;

  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > v_item.max_stack THEN
    RAISE EXCEPTION 'INVALID_QUANTITY: buy between 1 and % at a time', v_item.max_stack
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: no user with id %', p_user_id USING ERRCODE = 'P0002';
  END IF;

  SELECT quantity INTO v_owned
    FROM public.user_inventory
   WHERE user_id = p_user_id AND item_key = p_item_key
     FOR UPDATE;
  v_owned := COALESCE(v_owned, 0);

  IF v_owned + p_quantity > v_item.max_stack THEN
    RAISE EXCEPTION 'INVENTORY_FULL: you can carry at most % of these and already have %', v_item.max_stack, v_owned
      USING ERRCODE = 'P0001';
  END IF;

  IF v_item.purchase_cooldown_seconds > 0 THEN
    SELECT MAX(created_at) INTO v_last
      FROM public.shop_purchases
     WHERE user_id = p_user_id AND item_key = p_item_key;
    IF v_last IS NOT NULL AND v_last + make_interval(secs => v_item.purchase_cooldown_seconds) > now() THEN
      v_wait := CEIL(EXTRACT(EPOCH FROM (v_last + make_interval(secs => v_item.purchase_cooldown_seconds) - now())) / 60.0);
      RAISE EXCEPTION 'ON_COOLDOWN: % can be bought again in % minute(s)', v_item.name, v_wait
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Raises INSUFFICIENT_GOLD if the balance cannot cover it.
  v_spend := public.spend_gold(
    p_user_id, v_item.price_gold * p_quantity, 'shop_purchase', NULL, 'shop:' || p_request_id
  );

  INSERT INTO public.shop_purchases (user_id, item_key, quantity, price_total, ledger_id, request_id)
  VALUES (p_user_id, p_item_key, p_quantity, v_item.price_gold * p_quantity,
          (v_spend->>'ledger_id')::UUID, p_request_id);

  INSERT INTO public.user_inventory (user_id, item_key, quantity)
  VALUES (p_user_id, p_item_key, p_quantity)
  ON CONFLICT (user_id, item_key) DO UPDATE
    SET quantity = public.user_inventory.quantity + EXCLUDED.quantity,
        updated_at = now();

  RETURN jsonb_build_object(
    'success', TRUE,
    'duplicate', FALSE,
    'item_key', p_item_key,
    'quantity_owned', v_owned + p_quantity,
    'spent', v_item.price_gold * p_quantity,
    'balance', (v_spend->>'balance')::INTEGER
  );
END;
$$;


ALTER FUNCTION "public"."purchase_item"("p_user_id" "uuid", "p_item_key" "text", "p_quantity" integer, "p_request_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quit_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_run public.dungeon_runs;
BEGIN
  SELECT * INTO v_run FROM public.dungeon_runs
   WHERE battle_id = p_battle_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_IN_BATTLE: you are not part of this battle' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.dungeon_assignments SET status = 'cancelled', ended_at = now()
   WHERE run_id = v_run.id AND status = 'active';

  UPDATE public.dungeon_runs SET status = 'quit', ended_at = now() WHERE id = v_run.id;

  -- No caller passed: the person leaving must not count as present for the
  -- outage grace, and a party left silent behind them should stay suspended
  -- rather than be judged on their way out.
  PERFORM public.settle_dungeon_time(p_battle_id);

  RETURN jsonb_build_object('success', TRUE, 'status', 'quit');
END;
$$;


ALTER FUNCTION "public"."quit_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rate_plan_session"("p_user_id" "uuid", "p_plan_id" "uuid", "p_session_key" "text", "p_day" "date", "p_rating" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_plan   public.training_plans%ROWTYPE;
  v_index  INTEGER;
  v_before INTEGER;
  v_after  INTEGER;
  v_delta  INTEGER;
BEGIN
  v_delta := CASE p_rating WHEN 'too_easy' THEN 1 WHEN 'just_right' THEN 0 WHEN 'too_hard' THEN -1 END;
  IF v_delta IS NULL THEN
    RAISE EXCEPTION 'INVALID_RATING: rating must be too_easy, just_right or too_hard';
  END IF;
  SELECT * INTO v_plan FROM public.training_plans
   WHERE id = p_plan_id AND user_id = p_user_id AND status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PLAN_NOT_FOUND: that plan is not your current plan';
  END IF;

  SELECT (i - 1)::int INTO v_index
    FROM jsonb_array_elements(v_plan.sessions) WITH ORDINALITY AS s(e, i)
   WHERE s.e->>'key' = p_session_key;
  IF v_index IS NULL THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND: that session is not in your plan';
  END IF;

  IF p_day IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.training_plan_days WHERE plan_id = p_plan_id AND day = p_day AND session_key = p_session_key) THEN
      RAISE EXCEPTION 'DAY_NOT_FOUND: that day does not use this session';
    END IF;
    IF EXISTS (SELECT 1 FROM public.training_plan_feedback WHERE plan_id = p_plan_id AND day = p_day) THEN
      RAISE EXCEPTION 'ALREADY_RATED: you already rated that day';
    END IF;
  END IF;

  v_before := coalesce((v_plan.sessions->v_index->>'level')::int, 0);
  v_after := greatest(-3, least(3, v_before + v_delta));
  UPDATE public.training_plans
     SET sessions = jsonb_set(sessions, ARRAY[v_index::text, 'level'], to_jsonb(v_after))
   WHERE id = p_plan_id;

  INSERT INTO public.training_plan_feedback (user_id, plan_id, day, session_key, rating, level_before, level_after)
  VALUES (p_user_id, p_plan_id, p_day, p_session_key, p_rating, v_before, v_after);

  RETURN jsonb_build_object('session_key', p_session_key, 'level_before', v_before, 'level_after', v_after);
END;
$$;


ALTER FUNCTION "public"."rate_plan_session"("p_user_id" "uuid", "p_plan_id" "uuid", "p_session_key" "text", "p_day" "date", "p_rating" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_admin_action"("p_actor_user_id" "uuid", "p_action" "text", "p_target_type" "text", "p_target_id" "text", "p_metadata" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_role TEXT;
  v_id   UUID;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id = p_actor_user_id;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'UNKNOWN_USER: actor not found';
  END IF;

  INSERT INTO public.admin_audit_log (actor_user_id, actor_role, action, target_type, target_id, metadata)
  VALUES (p_actor_user_id, v_role, p_action, p_target_type, p_target_id, coalesce(p_metadata, '{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."record_admin_action"("p_actor_user_id" "uuid", "p_action" "text", "p_target_type" "text", "p_target_id" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_consent"("p_user_id" "uuid", "p_consent_type" "text", "p_notice_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_current TEXT;
  v_row     public.user_consents%ROWTYPE;
BEGIN
  IF p_consent_type NOT IN ('privacy_notice', 'camera', 'gps', 'ai_features', 'verification') THEN
    RAISE EXCEPTION 'INVALID_CONSENT_TYPE: % is not an acknowledgement notice', p_consent_type;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'UNKNOWN_USER: account not found';
  END IF;

  v_current := public.current_notice_version(p_consent_type);
  IF v_current IS NULL OR p_notice_version IS DISTINCT FROM v_current THEN
    RAISE EXCEPTION 'NOTICE_VERSION_OUTDATED: this notice has been updated. Please read the current version.';
  END IF;

  SELECT * INTO v_row FROM public.user_consents
  WHERE user_id = p_user_id AND consent_type = p_consent_type
  ORDER BY acknowledged_at DESC, id DESC LIMIT 1;

  IF NOT FOUND OR v_row.notice_version <> v_current THEN
    INSERT INTO public.user_consents (user_id, consent_type, notice_version, decision)
    VALUES (p_user_id, p_consent_type, v_current, 'acknowledged')
    RETURNING * INTO v_row;
  END IF;

  RETURN jsonb_build_object('consent_type', v_row.consent_type, 'notice_version', v_row.notice_version,
                            'decision', v_row.decision, 'acknowledged_at', v_row.acknowledged_at);
END;
$$;


ALTER FUNCTION "public"."record_consent"("p_user_id" "uuid", "p_consent_type" "text", "p_notice_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_user_commodity_price"("p_user_id" "uuid", "p_commodity_slug" "text", "p_price_php" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_commodity public.market_commodities%ROWTYPE;
  v_row       public.user_commodity_prices%ROWTYPE;
BEGIN
  SELECT * INTO v_commodity FROM public.market_commodities WHERE slug = p_commodity_slug AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'UNKNOWN_COMMODITY: that item isn''t in the price list.';
  END IF;

  INSERT INTO public.user_commodity_prices (user_id, commodity_id, unit, price_php)
  VALUES (p_user_id, v_commodity.id, v_commodity.purchase_unit, round(p_price_php, 2))
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'commodity', v_commodity.slug, 'unit', v_row.unit,
    'price_php', v_row.price_php, 'entered_at', v_row.entered_at
  );
END;
$$;


ALTER FUNCTION "public"."record_user_commodity_price"("p_user_id" "uuid", "p_commodity_slug" "text", "p_price_php" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_user_streak"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id UUID := COALESCE(NEW.user_id, OLD.user_id);
BEGIN
  UPDATE public.users
     SET streak = COALESCE((public.compute_streak(v_user_id)->>'current_streak')::INTEGER, 0)
   WHERE id = v_user_id;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."refresh_user_streak"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refuse_price_history_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  RAISE EXCEPTION 'PRICE_HISTORY_IMMUTABLE: prices are kept as recorded; add a new row instead of changing %', TG_TABLE_NAME;
END;
$$;


ALTER FUNCTION "public"."refuse_price_history_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refuse_record_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  RAISE EXCEPTION 'RECORD_IMMUTABLE: % rows are kept as written; add a new row instead', TG_TABLE_NAME;
END;
$$;


ALTER FUNCTION "public"."refuse_record_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."replace_active_plan"("p_user_id" "uuid", "p_plan" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_id UUID;
BEGIN
  IF jsonb_typeof(p_plan->'days') <> 'array' OR jsonb_array_length(p_plan->'days') <> 28 THEN
    RAISE EXCEPTION 'INVALID_PLAN: a plan has 28 days';
  END IF;
  UPDATE public.training_plans SET status = 'replaced' WHERE user_id = p_user_id AND status = 'active';

  INSERT INTO public.training_plans (user_id, start_date, end_date, generator_version, difficulty_step, sessions, notes)
  VALUES (p_user_id, (p_plan->>'startDate')::date, (p_plan->>'endDate')::date, (p_plan->>'version')::int,
          coalesce((p_plan->>'difficultyStep')::int, 0), p_plan->'sessions', coalesce(p_plan->'notes', '[]'::jsonb))
  RETURNING id INTO v_id;

  INSERT INTO public.training_plan_days (plan_id, day, session_key)
  SELECT v_id, (d->>'day')::date, nullif(d->>'session', '')
    FROM jsonb_array_elements(p_plan->'days') AS d;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."replace_active_plan"("p_user_id" "uuid", "p_plan" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_specialization_affinity"("p_focus_type" "text", "p_exercise" "text", "p_primary_attribute" "text") RETURNS numeric
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(
    (SELECT sa.multiplier FROM public.specialization_affinity sa
      WHERE sa.focus_type = p_focus_type
        AND sa.match_type = 'exercise'
        AND sa.match_value = p_exercise
      LIMIT 1),
    (SELECT sa.multiplier FROM public.specialization_affinity sa
      WHERE sa.focus_type = p_focus_type
        AND sa.match_type = 'attribute'
        AND sa.match_value = p_primary_attribute
      LIMIT 1),
    1.0
  );
$$;


ALTER FUNCTION "public"."resolve_specialization_affinity"("p_focus_type" "text", "p_exercise" "text", "p_primary_attribute" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_specialization_rank"("p_focus_type" "text", "p_xp" integer) RETURNS TABLE("rank_name" "text", "tier_index" integer, "sub_rank" integer, "tier_min_xp" integer, "next_rank_name" "text", "next_tier_min_xp" integer, "xp_to_next_sub_rank" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_rank_name    TEXT;
  v_tier_index   INTEGER;
  v_tier_min     INTEGER;
  v_sub_ranks    INTEGER;
  v_top_span     INTEGER;
  v_next_name    TEXT;
  v_next_min     INTEGER;
  v_band         NUMERIC;
  v_sub_rank     INTEGER;
  v_sub_next     INTEGER;
BEGIN
  SELECT rt.rank_name, rt.tier_index, rt.min_xp, rt.sub_ranks, rt.sub_rank_span_xp
    INTO v_rank_name, v_tier_index, v_tier_min, v_sub_ranks, v_top_span
    FROM public.rank_thresholds rt
   WHERE rt.focus_type = p_focus_type
     AND rt.min_xp <= GREATEST(p_xp, 0)
   ORDER BY rt.min_xp DESC
   LIMIT 1;

  IF v_rank_name IS NULL THEN
    RAISE EXCEPTION 'MISSING_RANK_LADDER: no rank_thresholds rows for focus_type "%"', p_focus_type
      USING ERRCODE = 'P0001';
  END IF;

  SELECT rt.rank_name, rt.min_xp
    INTO v_next_name, v_next_min
    FROM public.rank_thresholds rt
   WHERE rt.focus_type = p_focus_type
     AND rt.min_xp > GREATEST(p_xp, 0)
   ORDER BY rt.min_xp ASC
   LIMIT 1;

  -- Sub-ranks are interpolated, never stored. Inside a tier the band is an
  -- equal split of the gap to the next tier; the top tier has no next
  -- threshold, so it uses its own fixed span per sub-rank.
  IF v_next_min IS NOT NULL THEN
    v_band := GREATEST((v_next_min - v_tier_min)::NUMERIC / GREATEST(v_sub_ranks, 1), 1);
  ELSE
    v_band := GREATEST(COALESCE(v_top_span, 1), 1)::NUMERIC;
  END IF;

  v_sub_rank := LEAST(
    GREATEST(v_sub_ranks, 1),
    FLOOR((GREATEST(p_xp, 0) - v_tier_min) / v_band)::INTEGER + 1
  );

  -- XP remaining to the next sub-rank band. At the last sub-rank of the top
  -- tier there is nothing further to climb, so this is 0.
  IF v_sub_rank >= GREATEST(v_sub_ranks, 1) AND v_next_min IS NULL THEN
    v_sub_next := 0;
  ELSE
    v_sub_next := CEIL(v_tier_min + (v_sub_rank * v_band) - GREATEST(p_xp, 0))::INTEGER;
    v_sub_next := GREATEST(v_sub_next, 0);
  END IF;

  RETURN QUERY SELECT
    v_rank_name, v_tier_index, v_sub_rank, v_tier_min,
    v_next_name, v_next_min, v_sub_next;
END;
$$;


ALTER FUNCTION "public"."resolve_specialization_rank"("p_focus_type" "text", "p_xp" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_coach_status"("p_user_id" "uuid", "p_actor_id" "uuid", "p_by_self" boolean, "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_row public.verification_applications%ROWTYPE;
BEGIN
  IF NOT p_by_self AND coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED: give a reason for removing coach status';
  END IF;

  UPDATE public.verification_applications
     SET status = 'revoked', revoked_at = clock_timestamp(), revoked_by = p_actor_id,
         revoked_by_self = p_by_self, revoke_reason = nullif(btrim(p_reason), '')
   WHERE user_id = p_user_id AND kind = 'coach' AND status = 'approved'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_VERIFIED: this account is not a verified coach';
  END IF;
  RETURN jsonb_build_object('application_id', v_row.id, 'user_id', v_row.user_id, 'status', v_row.status);
END;
$$;


ALTER FUNCTION "public"."revoke_coach_status"("p_user_id" "uuid", "p_actor_id" "uuid", "p_by_self" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."roll_dungeon_reward"("p_event_id" "uuid", "p_user_id" "uuid", "p_seed" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_total  INTEGER;
  v_pick   BIGINT;
  v_row    RECORD;
  v_alt    RECORD;
  v_ratio  NUMERIC;
  v_comp   INTEGER;
BEGIN
  SELECT SUM(weight) INTO v_total FROM public.dungeon_reward_pool WHERE event_id = p_event_id;
  IF COALESCE(v_total, 0) = 0 THEN
    RETURN jsonb_build_object('kind', 'none');
  END IF;

  -- The seed is the battle's, mixed with the player: one party, one roll
  -- each. abs() because a bit-string cast can come back negative.
  v_pick := abs(('x' || substr(md5(p_seed::TEXT || ':' || p_user_id::TEXT), 1, 8))::BIT(32)::BIGINT) % v_total;

  -- Walk the cumulative weights. Ordered by id so the same seed always lands
  -- on the same row.
  SELECT * INTO v_row FROM (
    SELECT p.id, p.collectible_id, p.gold_amount, p.weight,
           SUM(p.weight) OVER (ORDER BY p.id ROWS UNBOUNDED PRECEDING) AS running
      FROM public.dungeon_reward_pool p
     WHERE p.event_id = p_event_id
  ) q WHERE q.running > v_pick ORDER BY q.running LIMIT 1;

  -- A plain gold entry: nothing to duplicate.
  IF v_row.collectible_id IS NULL THEN
    RETURN jsonb_build_object('kind', 'gold', 'gold', v_row.gold_amount);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_collectibles
     WHERE user_id = p_user_id AND collectible_id = v_row.collectible_id
  ) THEN
    RETURN jsonb_build_object(
      'kind', 'collectible', 'collectible_id', v_row.collectible_id,
      'duplicate', FALSE,
      'name', (SELECT name FROM public.collectibles WHERE id = v_row.collectible_id),
      'rarity', (SELECT rarity FROM public.collectibles WHERE id = v_row.collectible_id)
    );
  END IF;

  -- Already owned. Try anything else in this pool they do not have, taking
  -- the rarest first so a duplicate is not quietly downgraded to the most
  -- common thing available.
  SELECT c.id, c.name, c.rarity INTO v_alt
    FROM public.dungeon_reward_pool p
    JOIN public.collectibles c ON c.id = p.collectible_id
    JOIN public.rarities r ON r.key = c.rarity
   WHERE p.event_id = p_event_id
     AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM public.user_collectibles uc
                      WHERE uc.user_id = p_user_id AND uc.collectible_id = c.id)
   ORDER BY r.sort_order DESC, c.id
   LIMIT 1;

  IF v_alt.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'kind', 'collectible', 'collectible_id', v_alt.id, 'duplicate', TRUE,
      'name', v_alt.name, 'rarity', v_alt.rarity,
      'instead_of', (SELECT name FROM public.collectibles WHERE id = v_row.collectible_id)
    );
  END IF;

  -- They own the whole pool. Pay what the duplicate was worth.
  SELECT COALESCE((value->>'duplicate_gold_ratio')::NUMERIC, 0.5) INTO v_ratio
    FROM public.game_config WHERE key = 'dungeon_rewards';
  SELECT GREATEST(FLOOR(gold_value * v_ratio)::INTEGER, 1) INTO v_comp
    FROM public.collectibles WHERE id = v_row.collectible_id;

  RETURN jsonb_build_object(
    'kind', 'compensation', 'gold', v_comp, 'duplicate', TRUE,
    'instead_of', (SELECT name FROM public.collectibles WHERE id = v_row.collectible_id)
  );
END;
$$;


ALTER FUNCTION "public"."roll_dungeon_reward"("p_event_id" "uuid", "p_user_id" "uuid", "p_seed" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_foods"("p_query" "text", "p_limit" integer DEFAULT 8) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions', 'pg_temp'
    AS $$
  WITH q AS (
    -- LIKE wildcards are stripped so a query can't turn into "match everything".
    SELECT lower(regexp_replace(trim(coalesce(p_query, '')), '[%_\\]', '', 'g')) AS t
  ),
  -- Fuzzy (trigram) matching is only for when the words don't appear at all —
  -- typos like "itlug" or "tokua". When the query does appear somewhere, fuzzy
  -- matches are noise: "gata" pulled in corned beef "de lata" and "tahong"
  -- pulled in "talong" in the dry run.
  direct AS (
    SELECT EXISTS (SELECT 1 FROM public.foods f, q WHERE f.active AND f.search_text LIKE '%' || q.t || '%') AS any_direct
  ),
  ranked AS (
    SELECT f.*,
      CASE
        WHEN lower(f.name) = q.t
          OR EXISTS (SELECT 1 FROM unnest(f.local_names || f.aliases) n WHERE lower(n) = q.t) THEN 3
        WHEN lower(f.name) LIKE q.t || '%'
          OR EXISTS (SELECT 1 FROM unnest(f.local_names || f.aliases) n WHERE lower(n) LIKE q.t || '%') THEN 2
        WHEN f.search_text LIKE '%' || q.t || '%' THEN 1
        ELSE 0
      END AS tier,
      word_similarity(q.t, f.search_text) AS sim
    FROM public.foods f, q, direct
    WHERE f.active
      AND char_length(q.t) >= 2
      AND (f.search_text LIKE '%' || q.t || '%'
           OR (NOT direct.any_direct AND word_similarity(q.t, f.search_text) >= 0.4))
  ),
  top AS (
    SELECT * FROM ranked
    ORDER BY tier DESC, sim DESC, name
    LIMIT greatest(1, least(coalesce(p_limit, 8), 20))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'food', jsonb_build_object(
      'food_id', t.id,
      'slug', t.slug,
      'name', t.name,
      'description', t.description,
      'local_names', to_jsonb(t.local_names),
      'category', t.category,
      'region', t.region,
      'preparation', t.preparation,
      'brand', t.brand,
      'nutrition', jsonb_build_object(
        'basis', 'per_100g',
        'calories', t.calories, 'protein', t.protein, 'carbs', t.carbs,
        'fat', t.fat, 'fiber', t.fiber, 'sugar', t.sugar),
      'source', t.source,
      'source_reference', t.source_reference,
      'is_estimate', t.is_estimate,
      'estimate_note', t.estimate_note),
    'servings', coalesce((
      SELECT jsonb_agg(jsonb_build_object('label', s.label, 'grams', s.grams, 'is_estimate', s.is_estimate) ORDER BY s.sort_order)
        FROM public.food_servings s WHERE s.food_id = t.id), '[]'::jsonb)
  ) ORDER BY t.tier DESC, t.sim DESC, t.name), '[]'::jsonb)
  FROM top t
$$;


ALTER FUNCTION "public"."search_foods"("p_query" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_plan_day_status"("p_user_id" "uuid", "p_plan_id" "uuid", "p_day" "date", "p_status" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_row public.training_plan_days%ROWTYPE;
BEGIN
  IF p_status NOT IN ('planned', 'done', 'skipped') THEN
    RAISE EXCEPTION 'INVALID_STATUS: status must be planned, done or skipped';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.training_plans WHERE id = p_plan_id AND user_id = p_user_id AND status = 'active') THEN
    RAISE EXCEPTION 'PLAN_NOT_FOUND: that plan is not your current plan';
  END IF;
  SELECT * INTO v_row FROM public.training_plan_days WHERE plan_id = p_plan_id AND day = p_day FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DAY_NOT_FOUND: that day is not in your plan';
  END IF;
  IF v_row.session_key IS NULL THEN
    RAISE EXCEPTION 'REST_DAY: that is a rest day';
  END IF;
  UPDATE public.training_plan_days
     SET status = p_status, status_at = CASE WHEN p_status = 'planned' THEN NULL ELSE now() END
   WHERE plan_id = p_plan_id AND day = p_day
  RETURNING * INTO v_row;
  RETURN jsonb_build_object('day', v_row.day, 'session_key', v_row.session_key, 'status', v_row.status);
END;
$$;


ALTER FUNCTION "public"."set_plan_day_status"("p_user_id" "uuid", "p_plan_id" "uuid", "p_day" "date", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_relative_leaderboard"("p_user_id" "uuid", "p_opt_in" boolean, "p_notice_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_current TEXT := public.current_notice_version('relative_leaderboard');
  v_row     public.user_consents%ROWTYPE;
BEGIN
  IF p_opt_in IS NULL THEN
    RAISE EXCEPTION 'INVALID_CHOICE: opt_in must be true or false';
  END IF;
  IF p_opt_in AND p_notice_version IS DISTINCT FROM v_current THEN
    RAISE EXCEPTION 'NOTICE_VERSION_OUTDATED: this notice has been updated. Please read the current version.';
  END IF;

  UPDATE public.users SET relative_leaderboard_opt_in = p_opt_in WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'UNKNOWN_USER: account not found';
  END IF;

  INSERT INTO public.user_consents (user_id, consent_type, notice_version, decision)
  VALUES (p_user_id, 'relative_leaderboard', v_current, CASE WHEN p_opt_in THEN 'granted' ELSE 'withdrawn' END)
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('relative_leaderboard_opt_in', p_opt_in, 'notice_version', v_row.notice_version,
                            'decision', v_row.decision, 'acknowledged_at', v_row.acknowledged_at);
END;
$$;


ALTER FUNCTION "public"."set_relative_leaderboard"("p_user_id" "uuid", "p_opt_in" boolean, "p_notice_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_training_limits"("p_user_id" "uuid", "p_areas" "text"[], "p_notice_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_current TEXT := public.current_notice_version('training_limits');
  v_opt_in  BOOLEAN := coalesce(cardinality(p_areas), 0) > 0;
  v_row     public.user_consents%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'UNKNOWN_USER: account not found';
  END IF;
  IF v_opt_in AND p_notice_version IS DISTINCT FROM v_current THEN
    RAISE EXCEPTION 'NOTICE_VERSION_OUTDATED: this notice has been updated. Please read the current version.';
  END IF;

  IF v_opt_in THEN
    INSERT INTO public.training_limits (user_id, areas, updated_at) VALUES (p_user_id, p_areas, now())
    ON CONFLICT (user_id) DO UPDATE SET areas = EXCLUDED.areas, updated_at = now();
  ELSE
    DELETE FROM public.training_limits WHERE user_id = p_user_id;
  END IF;

  INSERT INTO public.user_consents (user_id, consent_type, notice_version, decision)
  VALUES (p_user_id, 'training_limits', v_current, CASE WHEN v_opt_in THEN 'granted' ELSE 'withdrawn' END)
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('areas', CASE WHEN v_opt_in THEN to_jsonb(p_areas) ELSE '[]'::jsonb END,
                            'decision', v_row.decision, 'notice_version', v_row.notice_version);
END;
$$;


ALTER FUNCTION "public"."set_training_limits"("p_user_id" "uuid", "p_areas" "text"[], "p_notice_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_user_budget"("p_user_id" "uuid", "p_daily_budget_php" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF p_daily_budget_php IS NULL THEN
    DELETE FROM public.user_budget_settings WHERE user_id = p_user_id;
    RETURN jsonb_build_object('daily_budget_php', NULL);
  END IF;

  INSERT INTO public.user_budget_settings (user_id, daily_budget_php, updated_at)
  VALUES (p_user_id, round(p_daily_budget_php, 2), now())
  ON CONFLICT (user_id) DO UPDATE
    SET daily_budget_php = EXCLUDED.daily_budget_php, updated_at = EXCLUDED.updated_at;

  RETURN jsonb_build_object('daily_budget_php', round(p_daily_budget_php, 2));
END;
$$;


ALTER FUNCTION "public"."set_user_budget"("p_user_id" "uuid", "p_daily_budget_php" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."settle_dungeon_time"("p_battle_id" "uuid", "p_caller_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle   public.dungeon_battles;
  v_rules    JSONB;
  v_penalty  JSONB;
  v_grace    INTEGER;
  v_revive   INTEGER;
  v_share    NUMERIC;
  v_stale    INTEGER;
  v_a        RECORD;
  v_loss     INTEGER;
  v_team     INTEGER;
  v_hp       INTEGER;
  v_live     INTEGER;
  v_silent   INTEGER;
  v_last     TIMESTAMPTZ;
  v_gap      NUMERIC;
BEGIN
  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id;
  IF NOT FOUND OR v_battle.status NOT IN ('active', 'paused') THEN RETURN; END IF;

  SELECT value INTO v_rules FROM public.game_config WHERE key = 'dungeon_rules';
  SELECT value INTO v_penalty FROM public.game_config WHERE key = 'dungeon_team_penalty';
  v_grace  := COALESCE((v_rules->>'disconnect_grace_seconds')::INTEGER, 120);
  v_revive := COALESCE((v_rules->>'revive_window_seconds')::INTEGER, 120);
  v_share  := COALESCE((v_penalty->>'teammate_share')::NUMERIC, 0.5);
  v_stale  := LEAST(v_grace, 30);

  -- The event's own clock ends everything.
  IF EXISTS (SELECT 1 FROM public.dungeon_events
              WHERE id = v_battle.event_id AND ends_at IS NOT NULL AND ends_at <= now()) THEN
    UPDATE public.dungeon_battles SET status = 'expired', ended_at = now() WHERE id = p_battle_id;
    UPDATE public.dungeon_runs SET status = 'failed', ended_at = now()
     WHERE battle_id = p_battle_id AND status IN ('joined', 'ready', 'active', 'disconnected', 'downed');
    RETURN;
  END IF;

  -- --- the outage grace -----------------------------------------------------
  -- One player going quiet is that player's problem. EVERY player going quiet
  -- in the same window is far more likely to be us, so the gap is given back
  -- instead of being charged to the party. Only meaningful with a party: for
  -- a solo run, "everyone is silent" and "the player left" are the same
  -- observation, and we must not hand a solo player free time for closing
  -- their phone.
  SELECT COUNT(*) FILTER (WHERE status IN ('active', 'disconnected')),
         COUNT(*) FILTER (WHERE status IN ('active', 'disconnected')
                            AND last_seen_at < now() - make_interval(secs => v_stale)),
         MAX(last_seen_at) FILTER (WHERE status IN ('active', 'disconnected'))
    INTO v_live, v_silent, v_last
    FROM public.dungeon_runs WHERE battle_id = p_battle_id;

  IF v_live >= 2 AND v_silent = v_live THEN
    v_gap := GREATEST(EXTRACT(EPOCH FROM now() - v_last), 0);

    -- Hand the time back before judging any deadline, or the outage would
    -- cost the party the very time it was meant to protect.
    UPDATE public.dungeon_assignments
       SET deadline_at = deadline_at + make_interval(secs => v_gap)
     WHERE battle_id = p_battle_id AND status = 'active' AND deadline_at IS NOT NULL;

    -- The revive window is a deadline too: someone down when the lights went
    -- out should not be out for good because of it.
    UPDATE public.dungeon_runs
       SET downed_at = downed_at + make_interval(secs => v_gap)
     WHERE battle_id = p_battle_id AND status = 'downed' AND downed_at IS NOT NULL;

    -- Recorded for the admin view and for working out what happened later.
    UPDATE public.dungeon_battles
       SET paused_at = COALESCE(paused_at, v_last), last_activity_at = now()
     WHERE id = p_battle_id;

    IF p_caller_id IS NULL THEN
      -- Nobody is here to resume it; leave the party suspended and judge
      -- nothing. The event's own clock is the backstop.
      UPDATE public.dungeon_battles SET status = 'paused' WHERE id = p_battle_id;
      RETURN;
    END IF;

    -- The caller is back, which is what ends the outage. Mark them seen now
    -- so the presence pass below does not fail the person who just returned.
    UPDATE public.dungeon_runs
       SET last_seen_at = now(),
           status = CASE WHEN status = 'disconnected' THEN 'active' ELSE status END
     WHERE battle_id = p_battle_id AND user_id = p_caller_id
       AND status IN ('active', 'disconnected');

    UPDATE public.dungeon_battles
       SET status = 'active', paused_at = NULL
     WHERE id = p_battle_id AND status = 'paused';

    -- Nothing else is judged this cycle: the gap has only just been repaid,
    -- and the remaining members deserve the grace window from now.
    RETURN;
  END IF;

  -- A party that was suspended and now has somebody active again.
  IF v_battle.status = 'paused' THEN
    UPDATE public.dungeon_battles SET status = 'active', paused_at = NULL WHERE id = p_battle_id;
  END IF;

  -- --- missed deadlines -----------------------------------------------------
  FOR v_a IN
    SELECT a.id, a.run_id, a.difficulty, r.combat_hp
      FROM public.dungeon_assignments a
      JOIN public.dungeon_runs r ON r.id = a.run_id
     WHERE a.battle_id = p_battle_id
       AND a.status = 'active'
       AND a.deadline_at IS NOT NULL
       AND a.deadline_at <= now()
  LOOP
    v_loss := COALESCE((v_penalty->>v_a.difficulty)::INTEGER, 12);
    v_team := GREATEST(FLOOR(v_loss * v_share)::INTEGER, 1);
    v_hp := GREATEST(v_a.combat_hp - v_loss, 0);

    UPDATE public.dungeon_assignments SET status = 'failed', ended_at = now() WHERE id = v_a.id;

    -- The player who missed it.
    UPDATE public.dungeon_runs
       SET combat_hp = v_hp,
           status = CASE WHEN v_hp = 0 THEN 'downed' ELSE status END,
           downed_at = CASE WHEN v_hp = 0 THEN COALESCE(downed_at, now()) ELSE downed_at END
     WHERE id = v_a.run_id;

    -- Everyone else still standing. This is the point of a party objective:
    -- one person stalling is everybody's problem.
    UPDATE public.dungeon_runs
       SET combat_hp = GREATEST(combat_hp - v_team, 0),
           status = CASE WHEN GREATEST(combat_hp - v_team, 0) = 0 THEN 'downed' ELSE status END,
           downed_at = CASE WHEN GREATEST(combat_hp - v_team, 0) = 0 THEN COALESCE(downed_at, now()) ELSE downed_at END
     WHERE battle_id = p_battle_id
       AND id <> v_a.run_id
       AND status IN ('active', 'disconnected');

    IF v_hp > 0 THEN
      PERFORM public.assign_dungeon_objective(p_battle_id, v_a.run_id);
    END IF;
  END LOOP;

  -- --- presence -------------------------------------------------------------
  UPDATE public.dungeon_runs
     SET status = 'disconnected'
   WHERE battle_id = p_battle_id AND status = 'active'
     AND last_seen_at < now() - make_interval(secs => v_stale);

  UPDATE public.dungeon_runs
     SET status = 'failed', ended_at = now()
   WHERE battle_id = p_battle_id AND status = 'disconnected'
     AND last_seen_at < now() - make_interval(secs => v_grace);

  -- Down and no Revive in time: out for good.
  UPDATE public.dungeon_runs
     SET status = 'out', ended_at = now()
   WHERE battle_id = p_battle_id AND status = 'downed'
     AND downed_at IS NOT NULL
     AND downed_at < now() - make_interval(secs => v_revive);

  IF NOT EXISTS (
    SELECT 1 FROM public.dungeon_runs
     WHERE battle_id = p_battle_id AND status IN ('joined', 'ready', 'active', 'disconnected', 'downed')
  ) THEN
    UPDATE public.dungeon_battles SET status = 'wiped', ended_at = now() WHERE id = p_battle_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."settle_dungeon_time"("p_battle_id" "uuid", "p_caller_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."settle_dungeon_victory"("p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle public.dungeon_battles;
  v_event  public.dungeon_events;
  v_total  NUMERIC;
  v_min    NUMERIC;
  v_sys    NUMERIC;
  v_run    RECORD;
  v_pct    NUMERIC;
  v_ok     BOOLEAN;
  v_xp     INTEGER;
  v_gold   INTEGER;
  v_drop   JSONB;
  v_got    BOOLEAN;
  v_paid   JSONB := '[]'::jsonb;
BEGIN
  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id;
  SELECT * INTO v_event FROM public.dungeon_events WHERE id = v_battle.event_id;

  SELECT COALESCE(SUM(total_damage), 0) INTO v_total
    FROM public.dungeon_runs WHERE battle_id = p_battle_id;

  SELECT COALESCE((value->>'min_contribution_percent')::NUMERIC, 10) INTO v_sys
    FROM public.game_config WHERE key = 'dungeon_rules';
  v_min := GREATEST(v_sys, COALESCE((v_event.config->>'min_contribution_percent')::NUMERIC, 0));

  v_xp   := COALESCE((v_event.config->>'reward_xp')::INTEGER, 0);
  v_gold := COALESCE((v_event.config->>'reward_gold')::INTEGER, 0);

  FOR v_run IN
    SELECT id, user_id, total_damage, status FROM public.dungeon_runs WHERE battle_id = p_battle_id
  LOOP
    v_pct := CASE WHEN v_total > 0 THEN (v_run.total_damage::NUMERIC / v_total) * 100 ELSE 0 END;
    -- Quitting forfeits; being downed or dropping out does not, as long as
    -- the work was already done.
    v_ok := v_run.status <> 'quit' AND v_pct >= v_min;

    UPDATE public.dungeon_runs
       SET contribution_percent = ROUND(v_pct, 2),
           reward_eligible = v_ok,
           status = CASE WHEN v_ok THEN 'cleared' ELSE status END,
           ended_at = COALESCE(ended_at, now())
     WHERE id = v_run.id;

    IF NOT v_ok THEN
      CONTINUE;
    END IF;

    INSERT INTO public.dungeon_clears (event_id, user_id, battle_id, contribution_percent)
    VALUES (v_event.id, v_run.user_id, p_battle_id, ROUND(v_pct, 2))
    ON CONFLICT (event_id, user_id) DO NOTHING;

    IF NOT FOUND THEN
      -- Already cleared this event: the run counted, the training counted,
      -- and nothing is paid.
      v_paid := v_paid || jsonb_build_object(
        'user_id', v_run.user_id, 'contribution_percent', ROUND(v_pct, 2),
        'xp', 0, 'gold', 0, 'first_clear', FALSE
      );
      CONTINUE;
    END IF;

    IF v_xp > 0 THEN
      PERFORM public.grant_bonus_xp(v_run.user_id, v_xp, 'dungeon_clear', v_event.id);
    END IF;
    IF v_gold > 0 THEN
      PERFORM public.award_gold(
        v_run.user_id, v_gold, 'dungeon_clear', v_event.id,
        format('dungeon_clear:%s:%s', v_event.id, v_run.user_id)
      );
    END IF;

    -- The drop.
    v_drop := public.roll_dungeon_reward(v_event.id, v_run.user_id, v_battle.seed);
    v_got := FALSE;

    IF v_drop->>'kind' = 'collectible' THEN
      INSERT INTO public.user_collectibles (user_id, collectible_id, source_type, source_id)
      VALUES (v_run.user_id, (v_drop->>'collectible_id')::UUID, 'dungeon_clear', v_event.id)
      ON CONFLICT (user_id, collectible_id) DO NOTHING;
      v_got := FOUND;

      -- The roll checked ownership, but between that read and this write a
      -- concurrent grant could have landed the same item. Rather than lose
      -- the reward, fall back to what the duplicate was worth.
      IF NOT v_got THEN
        PERFORM public.award_gold(
          v_run.user_id,
          GREATEST(FLOOR(COALESCE((SELECT gold_value FROM public.collectibles
                                    WHERE id = (v_drop->>'collectible_id')::UUID), 0) * 0.5)::INTEGER, 1),
          'dungeon_duplicate_compensation', v_event.id,
          format('dungeon_dupe:%s:%s', v_event.id, v_run.user_id)
        );
        v_drop := v_drop || jsonb_build_object('kind', 'compensation', 'raced', TRUE);
      END IF;

    ELSIF v_drop->>'kind' IN ('gold', 'compensation') THEN
      PERFORM public.award_gold(
        v_run.user_id, (v_drop->>'gold')::INTEGER,
        CASE WHEN v_drop->>'kind' = 'compensation'
             THEN 'dungeon_duplicate_compensation' ELSE 'dungeon_clear' END,
        v_event.id,
        format('dungeon_drop:%s:%s', v_event.id, v_run.user_id)
      );
    END IF;

    v_paid := v_paid || jsonb_build_object(
      'user_id', v_run.user_id, 'contribution_percent', ROUND(v_pct, 2),
      'xp', v_xp, 'gold', v_gold, 'first_clear', TRUE, 'drop', v_drop
    );
  END LOOP;

  RETURN jsonb_build_object(
    'cleared', TRUE, 'total_damage', v_total, 'min_contribution_percent', v_min, 'rewards', v_paid
  );
END;
$$;


ALTER FUNCTION "public"."settle_dungeon_victory"("p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."spend_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid" DEFAULT NULL::"uuid", "p_idempotency_key" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_balance INTEGER;
  v_id      UUID;
  v_prior   INTEGER;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: a spend must be a positive cost, got %', p_amount
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: no user with id %', p_user_id
      USING ERRCODE = 'P0002';
  END IF;

  -- A retried purchase must not charge twice, and must not read as a failure.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT -amount INTO v_prior
      FROM public.gold_ledger
     WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'spent', FALSE, 'duplicate', TRUE, 'amount', v_prior,
        'balance', public.gold_balance(p_user_id)
      );
    END IF;
  END IF;

  v_balance := public.gold_balance(p_user_id);
  IF v_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_GOLD: balance % cannot cover %', v_balance, p_amount
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.gold_ledger (user_id, amount, reason, source_id, idempotency_key)
  VALUES (p_user_id, -p_amount, p_reason, p_source_id, p_idempotency_key)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'spent', TRUE, 'duplicate', FALSE, 'amount', p_amount,
    'ledger_id', v_id, 'balance', v_balance - p_amount
  );
END;
$$;


ALTER FUNCTION "public"."spend_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid", "p_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle public.dungeon_battles;
  v_run    RECORD;
BEGIN
  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATTLE_NOT_FOUND: no battle with that id' USING ERRCODE = 'P0001';
  END IF;
  IF v_battle.leader_id IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'NOT_LEADER: only the party leader can start the fight' USING ERRCODE = 'P0001';
  END IF;
  IF v_battle.status <> 'forming' THEN
    RAISE EXCEPTION 'ALREADY_STARTED: this battle is already %', v_battle.status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.dungeon_battles
     SET status = 'active', started_at = now(), last_activity_at = now()
   WHERE id = p_battle_id;

  FOR v_run IN SELECT id FROM public.dungeon_runs WHERE battle_id = p_battle_id AND status IN ('joined', 'ready') LOOP
    UPDATE public.dungeon_runs SET status = 'active', last_seen_at = now() WHERE id = v_run.id;
    PERFORM public.assign_dungeon_objective(p_battle_id, v_run.id);
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'battle_id', p_battle_id, 'status', 'active');
END;
$$;


ALTER FUNCTION "public"."start_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_cfg   JSONB;
  v_a     public.dungeon_assignments;
  v_run   public.dungeon_runs;
  v_secs  INTEGER;
  v_bonus INTEGER;
BEGIN
  SELECT r.* INTO v_run
    FROM public.dungeon_runs r
   WHERE r.battle_id = p_battle_id AND r.user_id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_IN_BATTLE: you are not part of this battle' USING ERRCODE = 'P0001';
  END IF;

  SELECT a.* INTO v_a
    FROM public.dungeon_assignments a
   WHERE a.run_id = v_run.id AND a.status = 'active'
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_OBJECTIVE: you have no objective waiting' USING ERRCODE = 'P0001';
  END IF;

  IF v_a.started_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', TRUE, 'already_started', TRUE,
                              'deadline_at', v_a.deadline_at);
  END IF;

  SELECT value INTO v_cfg FROM public.game_config WHERE key = 'dungeon_objectives';
  v_secs := COALESCE((v_cfg->'objective_seconds'->>v_a.difficulty)::INTEGER, 360);
  v_bonus := v_run.bonus_seconds;

  UPDATE public.dungeon_assignments
     SET started_at = now(), deadline_at = now() + make_interval(secs => v_secs + v_bonus)
   WHERE id = v_a.id;

  IF v_bonus > 0 THEN
    UPDATE public.dungeon_runs SET bonus_seconds = 0 WHERE id = v_run.id;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE, 'assignment_id', v_a.id, 'exercise', v_a.exercise,
    'base_seconds', v_secs, 'bonus_seconds', v_bonus,
    'deadline_at', now() + make_interval(secs => v_secs + v_bonus)
  );
END;
$$;


ALTER FUNCTION "public"."start_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_mission_attempt"("p_user_id" "uuid", "p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_mission     public.missions;
  v_unlocked    BOOLEAN;
  v_is_replay   BOOLEAN;
  v_attempt_id  UUID;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'MISSION_NOT_FOUND: no active mission with id %', p_mission_id
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: no user with id %', p_user_id USING ERRCODE = 'P0002';
  END IF;

  v_unlocked := v_mission.level_number = 1 OR EXISTS (
    SELECT 1
      FROM public.mission_clears pc
      JOIN public.missions pm ON pm.id = pc.mission_id
     WHERE pc.user_id = p_user_id
       AND pm.chapter_id = v_mission.chapter_id
       AND pm.level_number = v_mission.level_number - 1
  );

  IF NOT v_unlocked THEN
    RAISE EXCEPTION 'MISSION_LOCKED: clear level % of this chapter first', v_mission.level_number - 1
      USING ERRCODE = 'P0001';
  END IF;

  -- Only one attempt can be live at a time (a partial unique index enforces
  -- it too). Starting a new one gives up the old one rather than erroring:
  -- an abandoned attempt costs nothing, and a stuck attempt the player can't
  -- clear would otherwise lock them out of the board.
  UPDATE public.mission_attempts
     SET status = 'abandoned', ended_at = now()
   WHERE user_id = p_user_id AND status = 'active';

  v_is_replay := EXISTS (
    SELECT 1 FROM public.mission_clears WHERE user_id = p_user_id AND mission_id = p_mission_id
  );

  INSERT INTO public.mission_attempts (
    user_id, mission_id, boss_hp, expires_at, is_replay, current_sequence
  ) VALUES (
    p_user_id, p_mission_id, v_mission.max_hp,
    now() + make_interval(secs => v_mission.time_limit_seconds), v_is_replay, 1
  )
  RETURNING id INTO v_attempt_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'attempt_id', v_attempt_id,
    'mission_id', p_mission_id,
    'mission_name', v_mission.name,
    'boss_hp', v_mission.max_hp,
    'max_hp', v_mission.max_hp,
    'expires_at', now() + make_interval(secs => v_mission.time_limit_seconds),
    'is_replay', v_is_replay,
    'current_sequence', 1,
    'objectives', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'sequence', o.sequence,
               'exercise', o.exercise,
               'metric_type', e.metric_type,
               'target_value', o.target_value,
               'base_damage', o.base_damage,
               'time_limit_seconds', o.objective_time_limit_seconds
             ) ORDER BY o.sequence)
        FROM public.mission_objectives o
        JOIN public.exercises e ON e.name = o.exercise
       WHERE o.mission_id = p_mission_id), '[]'::jsonb)
  );
END;
$$;


ALTER FUNCTION "public"."start_mission_attempt"("p_user_id" "uuid", "p_mission_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_attempt   public.mission_attempts;
  v_objective public.mission_objectives;
  v_metric    TEXT;
BEGIN
  SELECT * INTO v_attempt
    FROM public.mission_attempts
   WHERE id = p_attempt_id AND user_id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND: no attempt % for this user', p_attempt_id
      USING ERRCODE = 'P0001';
  END IF;
  IF v_attempt.status <> 'active' THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_ACTIVE: this attempt is already %', v_attempt.status
      USING ERRCODE = 'P0001';
  END IF;
  IF now() > v_attempt.expires_at THEN
    UPDATE public.mission_attempts SET status = 'failed', ended_at = now() WHERE id = p_attempt_id;
    RETURN jsonb_build_object('success', FALSE, 'expired', TRUE, 'status', 'failed');
  END IF;

  SELECT o.* INTO v_objective
    FROM public.mission_objectives o
   WHERE o.mission_id = v_attempt.mission_id AND o.sequence = v_attempt.current_sequence;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_OBJECTIVE: attempt % has no objective at sequence %', p_attempt_id, v_attempt.current_sequence
      USING ERRCODE = 'P0001';
  END IF;

  SELECT metric_type INTO v_metric FROM public.exercises WHERE name = v_objective.exercise;

  UPDATE public.mission_attempts
     SET objective_started_at = now()
   WHERE id = p_attempt_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'objective_started_at', now(),
    'sequence', v_objective.sequence,
    'exercise', v_objective.exercise,
    'metric_type', v_metric,
    'target_value', v_objective.target_value,
    'expires_at', v_attempt.expires_at
  );
END;
$$;


ALTER FUNCTION "public"."start_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."streak_restore_candidate"("p_user_id" "uuid", "p_now" timestamp with time zone DEFAULT "now"()) RETURNS "date"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_tz      TEXT := public.game_timezone();
  v_today   DATE;
  v_max_age INTEGER;
  v_days    DATE[];
  v_day     DATE;
BEGIN
  v_today := (p_now AT TIME ZONE v_tz)::DATE;
  v_max_age := COALESCE(
    (SELECT (value->>'restore_max_age_days')::INTEGER FROM public.game_config WHERE key = 'streak_rules'),
    3
  );

  -- Counted days near the window, by the same rule as compute_streak.
  SELECT ARRAY_AGG(DISTINCT d) INTO v_days
    FROM (
      SELECT ((w.logged_at AT TIME ZONE 'UTC') AT TIME ZONE v_tz)::DATE AS d
        FROM public.workout_logs w
       WHERE w.user_id = p_user_id
         AND w.logged_at >= (p_now AT TIME ZONE 'UTC') - make_interval(days => v_max_age + 3)
      UNION
      SELECT s.covered_date
        FROM public.streak_shields s
       WHERE s.user_id = p_user_id
    ) counted;

  IF v_days IS NULL THEN
    RETURN NULL;
  END IF;

  FOR v_day IN
    SELECT g::DATE
      FROM generate_series((v_today - 1)::TIMESTAMP, (v_today - v_max_age)::TIMESTAMP, INTERVAL '-1 day') g
  LOOP
    IF NOT (v_day = ANY (v_days))
       AND (v_day - 1) = ANY (v_days)
       AND ((v_day + 1) = ANY (v_days) OR v_day + 1 = v_today)
    THEN
      RETURN v_day;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."streak_restore_candidate"("p_user_id" "uuid", "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric DEFAULT NULL::numeric, "p_workout_source" "text" DEFAULT 'camera'::"text", "p_weight_kg" numeric DEFAULT NULL::numeric, "p_assignment_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_battle   public.dungeon_battles;
  v_event    public.dungeon_events;
  v_run      public.dungeon_runs;
  v_own      public.dungeon_assignments;
  v_a        public.dungeon_assignments;
  v_owner    public.dungeon_runs;
  v_assist   BOOLEAN := FALSE;
  v_metric   TEXT;
  v_elapsed  NUMERIC;
  v_workout  JSONB;
  v_total    NUMERIC;
  v_damage   INTEGER;
  v_dealt    INTEGER;
  v_is_crit  BOOLEAN;
  v_boss_hp  INTEGER;
  v_result   UUID;
  v_sum      NUMERIC;
  v_given    INTEGER := 0;
  v_share    INTEGER;
  v_c        RECORD;
  v_credits  JSONB := '[]'::jsonb;
  v_next     JSONB;
  v_settled  JSONB := NULL;
BEGIN
  IF p_achieved IS NULL OR p_achieved <= 0 THEN
    RAISE EXCEPTION 'INVALID_RESULT: nothing was achieved' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATTLE_NOT_FOUND: no battle with that id' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.settle_dungeon_time(p_battle_id, p_user_id);
  SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = p_battle_id;

  IF v_battle.status NOT IN ('active', 'paused') THEN
    RETURN jsonb_build_object('success', FALSE, 'battle_status', v_battle.status,
                              'message', format('This battle is already %s.', v_battle.status));
  END IF;

  SELECT * INTO v_run FROM public.dungeon_runs
   WHERE battle_id = p_battle_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_IN_BATTLE: you are not part of this battle' USING ERRCODE = 'P0001';
  END IF;
  IF v_run.status NOT IN ('active', 'disconnected') THEN
    RETURN jsonb_build_object('success', FALSE, 'run_status', v_run.status,
                              'message', format('You are %s in this battle.', v_run.status));
  END IF;

  SELECT * INTO v_own FROM public.dungeon_assignments
   WHERE run_id = v_run.id AND status = 'active' FOR UPDATE;

  IF p_assignment_id IS NULL OR p_assignment_id = v_own.id THEN
    v_a := v_own;
    IF v_a.id IS NULL THEN
      RAISE EXCEPTION 'NO_OBJECTIVE: you have no objective to hand in' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- An assist: helping is done INSTEAD of your own set, never inside one.
    IF v_own.id IS NOT NULL AND v_own.started_at IS NOT NULL THEN
      RAISE EXCEPTION 'OWN_SET_RUNNING: finish your own objective before helping someone else'
        USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_a FROM public.dungeon_assignments
     WHERE id = p_assignment_id AND battle_id = p_battle_id AND status = 'active'
       FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NO_SUCH_OBJECTIVE: that objective is not open in this battle' USING ERRCODE = 'P0001';
    END IF;
    IF v_a.started_at IS NULL THEN
      RAISE EXCEPTION 'NOT_STARTED: your teammate has not started that objective yet' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_owner FROM public.dungeon_runs WHERE id = v_a.run_id FOR UPDATE;
    IF v_owner.status NOT IN ('active', 'disconnected') THEN
      RAISE EXCEPTION 'TEAMMATE_OUT: that teammate is % — there is nothing to help with', v_owner.status
        USING ERRCODE = 'P0001';
    END IF;

    v_assist := TRUE;
  END IF;

  SELECT * INTO v_event FROM public.dungeon_events WHERE id = v_battle.event_id;
  SELECT metric_type INTO v_metric FROM public.exercises WHERE name = v_a.exercise;
  v_elapsed := EXTRACT(EPOCH FROM now() - COALESCE(v_a.started_at, v_a.assigned_at));

  PERFORM public.assert_result_plausible(v_a.exercise, v_metric, p_achieved, v_elapsed);

  -- The work is logged to whoever did it, assist or not.
  v_workout := public.log_workout_and_progress(
    p_user_id, v_a.exercise, 1,
    CASE WHEN v_metric = 'reps' THEN FLOOR(p_achieved)::INTEGER ELSE NULL END,
    p_form_quality, p_workout_source, p_weight_kg,
    CASE WHEN v_metric <> 'reps' THEN FLOOR(p_achieved)::INTEGER ELSE NULL END,
    NULL
  );

  v_total := v_a.progress + p_achieved;

  -- Every contribution is recorded, cleared or not. Damage starts at zero and
  -- is filled in when the objective actually falls — that is what lets the
  -- credit be split by who did what.
  INSERT INTO public.dungeon_objective_results (
    assignment_id, actor_run_id, workout_log_id, achieved_value, form_quality,
    damage, is_assist, is_crit, elapsed_seconds
  ) VALUES (
    v_a.id, v_run.id, (v_workout->>'workout_log_id')::UUID, p_achieved, p_form_quality,
    0, v_assist, FALSE, ROUND(v_elapsed)
  )
  RETURNING id INTO v_result;

  IF v_total < v_a.target_value THEN
    UPDATE public.dungeon_assignments SET progress = v_total WHERE id = v_a.id;

    RETURN jsonb_build_object(
      'success', TRUE, 'objective_cleared', FALSE, 'is_assist', v_assist,
      'achieved', p_achieved, 'progress', v_total, 'target', v_a.target_value, 'damage', 0,
      'boss_hp', v_battle.boss_hp, 'boss_max_hp', v_event.boss_max_hp, 'workout', v_workout,
      'message', format('%s of %s — logged as training; the objective is still open.',
                        v_total, v_a.target_value)
    );
  END IF;

  -- Form quality of the set that finished it decides the crit.
  SELECT d.damage, d.is_crit INTO v_damage, v_is_crit
    FROM public.mission_damage(v_a.base_damage, p_form_quality) d;

  v_boss_hp := GREATEST(v_battle.boss_hp - v_damage, 0);
  v_dealt := v_battle.boss_hp - v_boss_hp;

  UPDATE public.dungeon_assignments
     SET status = 'cleared', progress = v_total, ended_at = now()
   WHERE id = v_a.id;
  UPDATE public.dungeon_objective_results SET is_crit = v_is_crit WHERE id = v_result;

  -- Divide the damage across everyone who contributed to this objective, in
  -- proportion to how much of it they did. Ordered so the player who landed
  -- the finishing set is last and absorbs the rounding remainder, which keeps
  -- the credited total exactly equal to the damage the boss took.
  SELECT SUM(achieved_value) INTO v_sum
    FROM public.dungeon_objective_results WHERE assignment_id = v_a.id;

  FOR v_c IN
    SELECT actor_run_id, SUM(achieved_value) AS did
      FROM public.dungeon_objective_results
     WHERE assignment_id = v_a.id
     GROUP BY actor_run_id
     ORDER BY (actor_run_id = v_run.id), actor_run_id
  LOOP
    IF v_c.actor_run_id = v_run.id THEN
      v_share := v_dealt - v_given;              -- the remainder, to the finisher
    ELSE
      v_share := FLOOR(v_dealt * v_c.did / NULLIF(v_sum, 0))::INTEGER;
    END IF;
    v_given := v_given + v_share;

    UPDATE public.dungeon_runs
       SET total_damage = total_damage + v_share
     WHERE id = v_c.actor_run_id;

    -- Spread across that player's rows for this objective; the last one takes
    -- whatever is left so the rows sum to their share.
    UPDATE public.dungeon_objective_results
       SET damage = v_share
     WHERE id = (SELECT id FROM public.dungeon_objective_results
                  WHERE assignment_id = v_a.id AND actor_run_id = v_c.actor_run_id
                  ORDER BY created_at DESC LIMIT 1);

    v_credits := v_credits || jsonb_build_object(
      'run_id', v_c.actor_run_id, 'contributed', v_c.did, 'damage', v_share,
      'is_me', v_c.actor_run_id = v_run.id
    );
  END LOOP;

  UPDATE public.dungeon_battles SET boss_hp = v_boss_hp, last_activity_at = now() WHERE id = p_battle_id;

  IF v_boss_hp = 0 THEN
    -- The conditional status flip is what makes settlement run exactly once,
    -- even if two players land a killing blow in the same instant.
    UPDATE public.dungeon_battles
       SET status = 'cleared', ended_at = now()
     WHERE id = p_battle_id AND status IN ('active', 'paused');
    IF FOUND THEN
      v_settled := public.settle_dungeon_victory(p_battle_id);
    END IF;
  ELSE
    -- The next objective goes to whoever OWNED the one that just cleared.
    v_next := public.assign_dungeon_objective(p_battle_id, v_a.run_id);
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'objective_cleared', TRUE,
    'is_assist', v_assist,
    'achieved', p_achieved,
    'progress', v_total,
    'target', v_a.target_value,
    'damage', v_damage,
    'damage_dealt', v_dealt,
    'damage_credits', v_credits,
    'is_crit', v_is_crit,
    'boss_hp', v_boss_hp,
    'boss_max_hp', v_event.boss_max_hp,
    'battle_cleared', v_boss_hp = 0,
    'next_objective', v_next,
    'settlement', v_settled,
    'workout', v_workout
  );
END;
$$;


ALTER FUNCTION "public"."submit_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric, "p_workout_source" "text", "p_weight_kg" numeric, "p_assignment_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric DEFAULT NULL::numeric, "p_workout_source" "text" DEFAULT 'camera'::"text", "p_weight_kg" numeric DEFAULT NULL::numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_attempt    public.mission_attempts;
  v_mission    public.missions;
  v_objective  public.mission_objectives;
  v_metric     TEXT;
  v_elapsed    NUMERIC;
  v_workout    JSONB;
  v_damage     INTEGER;
  v_dealt      INTEGER;
  v_is_crit    BOOLEAN;
  v_cleared    BOOLEAN;
  v_boss_hp    INTEGER;
  v_total      INTEGER;
  v_is_final   BOOLEAN;
  v_complete   BOOLEAN := FALSE;
  v_first_clear BOOLEAN := FALSE;
  v_grade      TEXT;
  v_avg_quality NUMERIC;
  v_grades     JSONB;
  v_xp_reward  JSONB;
  v_gold_reward JSONB;
  v_collectible BOOLEAN := FALSE;
  v_next_seq   INTEGER;
BEGIN
  IF p_achieved IS NULL OR p_achieved <= 0 THEN
    RAISE EXCEPTION 'INVALID_RESULT: nothing was achieved' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_attempt
    FROM public.mission_attempts
   WHERE id = p_attempt_id AND user_id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND: no attempt % for this user', p_attempt_id
      USING ERRCODE = 'P0001';
  END IF;
  IF v_attempt.status <> 'active' THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_ACTIVE: this attempt is already %', v_attempt.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Deadlines are judged here rather than by a scheduler: there is no cron in
  -- this project, and a timer the client owns could simply be ignored.
  IF now() > v_attempt.expires_at THEN
    UPDATE public.mission_attempts SET status = 'failed', ended_at = now() WHERE id = p_attempt_id;
    RETURN jsonb_build_object('success', FALSE, 'expired', TRUE, 'status', 'failed',
                              'message', 'The mission timer ran out.');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_attempt.mission_id;

  SELECT o.* INTO v_objective
    FROM public.mission_objectives o
   WHERE o.mission_id = v_attempt.mission_id AND o.sequence = v_attempt.current_sequence;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_OBJECTIVE: nothing to submit at sequence %', v_attempt.current_sequence
      USING ERRCODE = 'P0001';
  END IF;

  SELECT metric_type INTO v_metric FROM public.exercises WHERE name = v_objective.exercise;
  v_elapsed := EXTRACT(EPOCH FROM now() - COALESCE(v_attempt.objective_started_at, v_attempt.started_at));

  PERFORM public.assert_result_plausible(v_objective.exercise, v_metric, p_achieved, v_elapsed);

  -- The set is real training whatever the mission makes of it.
  v_workout := public.log_workout_and_progress(
    p_user_id,
    v_objective.exercise,
    1,
    CASE WHEN v_metric = 'reps' THEN FLOOR(p_achieved)::INTEGER ELSE NULL END,
    p_form_quality,
    p_workout_source,
    p_weight_kg,
    CASE WHEN v_metric <> 'reps' THEN FLOOR(p_achieved)::INTEGER ELSE NULL END,
    NULL
  );

  v_cleared := p_achieved >= v_objective.target_value;

  IF NOT v_cleared THEN
    RETURN jsonb_build_object(
      'success', TRUE,
      'objective_cleared', FALSE,
      'achieved', p_achieved,
      'target', v_objective.target_value,
      'shortfall', v_objective.target_value - p_achieved,
      'damage', 0,
      'damage_dealt', 0,
      'boss_hp', v_attempt.boss_hp,
      'max_hp', v_mission.max_hp,
      'current_sequence', v_attempt.current_sequence,
      'mission_complete', FALSE,
      'workout', v_workout,
      'message', format('%s of %s — the set counted as training, but the objective is still open.',
                        p_achieved, v_objective.target_value)
    );
  END IF;

  SELECT COUNT(*) INTO v_total FROM public.mission_objectives WHERE mission_id = v_attempt.mission_id;
  v_is_final := v_attempt.current_sequence >= v_total;

  SELECT d.damage, d.is_crit INTO v_damage, v_is_crit
    FROM public.mission_damage(v_objective.base_damage, p_form_quality) d;

  IF v_is_final THEN
    v_boss_hp := 0;
  ELSE
    v_boss_hp := GREATEST(v_attempt.boss_hp - v_damage, 1);
  END IF;
  v_dealt := v_attempt.boss_hp - v_boss_hp;

  -- UNIQUE(attempt_id, objective_id) makes a replayed request a no-op rather
  -- than double damage; the raise below also rolls back the workout it logged.
  INSERT INTO public.mission_objective_results (
    attempt_id, objective_id, workout_log_id, achieved_value, form_quality,
    damage, is_crit, success, elapsed_seconds
  ) VALUES (
    p_attempt_id, v_objective.id, (v_workout->>'workout_log_id')::UUID, p_achieved, p_form_quality,
    v_damage, v_is_crit, TRUE, ROUND(v_elapsed)
  )
  ON CONFLICT (attempt_id, objective_id) DO NOTHING;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ALREADY_SUBMITTED: objective % of this attempt is already recorded', v_objective.sequence
      USING ERRCODE = 'P0001';
  END IF;

  v_next_seq := v_attempt.current_sequence + 1;
  v_complete := v_is_final;

  UPDATE public.mission_attempts
     SET boss_hp = v_boss_hp,
         current_sequence = v_next_seq,
         objective_started_at = NULL,
         status = CASE WHEN v_complete THEN 'completed' ELSE 'active' END,
         ended_at = CASE WHEN v_complete THEN now() ELSE NULL END
   WHERE id = p_attempt_id;

  IF v_complete THEN
    SELECT AVG(COALESCE(form_quality, 0)) INTO v_avg_quality
      FROM public.mission_objective_results WHERE attempt_id = p_attempt_id;

    SELECT value INTO v_grades FROM public.game_config WHERE key = 'mission_grades';
    v_grade := CASE
      WHEN v_avg_quality >= COALESCE((v_grades->>'S')::NUMERIC, 0.95) THEN 'S'
      WHEN v_avg_quality >= COALESCE((v_grades->>'A')::NUMERIC, 0.85) THEN 'A'
      WHEN v_avg_quality >= COALESCE((v_grades->>'B')::NUMERIC, 0.70) THEN 'B'
      ELSE 'C'
    END;

    -- The clear row is the payout gate: if this insert does nothing, the
    -- mission was already cleared and nothing further is owed.
    INSERT INTO public.mission_clears (user_id, mission_id, attempt_id, grade)
    VALUES (p_user_id, v_attempt.mission_id, p_attempt_id, v_grade)
    ON CONFLICT (user_id, mission_id) DO NOTHING;

    v_first_clear := FOUND;

    IF v_first_clear THEN
      IF v_mission.reward_xp > 0 THEN
        v_xp_reward := public.grant_bonus_xp(p_user_id, v_mission.reward_xp, 'mission_first_clear', v_attempt.mission_id);
      END IF;
      IF v_mission.reward_gold > 0 THEN
        v_gold_reward := public.award_gold(
          p_user_id, v_mission.reward_gold, 'mission_first_clear', v_attempt.mission_id,
          format('mission_first_clear:%s:%s', v_attempt.mission_id, p_user_id)
        );
      END IF;
      IF v_mission.reward_collectible_id IS NOT NULL THEN
        INSERT INTO public.user_collectibles (user_id, collectible_id, source_type, source_id)
        VALUES (p_user_id, v_mission.reward_collectible_id, 'mission_first_clear', v_attempt.mission_id)
        ON CONFLICT (user_id, collectible_id) DO NOTHING;
        v_collectible := FOUND;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'objective_cleared', TRUE,
    'achieved', p_achieved,
    'target', v_objective.target_value,
    'damage', v_damage,
    'damage_dealt', v_dealt,
    'is_crit', v_is_crit,
    'is_final_blow', v_is_final,
    'boss_hp', v_boss_hp,
    'max_hp', v_mission.max_hp,
    'current_sequence', v_next_seq,
    'objective_total', v_total,
    'mission_complete', v_complete,
    'first_clear', v_first_clear,
    'grade', v_grade,
    'rewards', jsonb_build_object(
      'xp', CASE WHEN v_first_clear AND v_mission.reward_xp > 0 THEN v_mission.reward_xp ELSE 0 END,
      'gold', CASE WHEN v_first_clear AND COALESCE(v_gold_reward->>'awarded', 'false') = 'true' THEN v_mission.reward_gold ELSE 0 END,
      'collectible', v_collectible,
      'xp_detail', v_xp_reward
    ),
    'workout', v_workout
  );
END;
$$;


ALTER FUNCTION "public"."submit_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric, "p_workout_source" "text", "p_weight_kg" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."training_history_counts"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'active_weeks', count(DISTINCT date_trunc('week', logged_at)),
    'first_logged_at', min(logged_at),
    'last_logged_at', max(logged_at)
  )
  FROM public.workout_logs
  WHERE user_id = p_user_id;
$$;


ALTER FUNCTION "public"."training_history_counts"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."use_item"("p_user_id" "uuid", "p_item_key" "text", "p_context_type" "text" DEFAULT NULL::"text", "p_context_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_item     public.shop_items;
  v_qty      INTEGER;
  v_last     TIMESTAMPTZ;
  v_attempt  public.mission_attempts;
  v_run      public.dungeon_runs;
  v_battle   public.dungeon_battles;
  v_event    public.dungeon_events;
  v_a        public.dungeon_assignments;
  v_rules    JSONB;
  v_allowed  INTEGER;
  v_day      DATE;
  v_effect   JSONB;
  v_context  TEXT := p_context_type;
  v_wait     INTEGER;
  v_max_age  INTEGER;
  v_heal     INTEGER;
  v_hp       INTEGER;
  v_extend   INTEGER;
BEGIN
  SELECT * INTO v_item FROM public.shop_items WHERE key = p_item_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ITEM_NOT_FOUND: unknown item' USING ERRCODE = 'P0001';
  END IF;

  SELECT quantity INTO v_qty
    FROM public.user_inventory
   WHERE user_id = p_user_id AND item_key = p_item_key
     FOR UPDATE;

  IF COALESCE(v_qty, 0) < 1 THEN
    RAISE EXCEPTION 'NOT_OWNED: you do not have a % — the shop sells them', v_item.name
      USING ERRCODE = 'P0001';
  END IF;

  IF v_item.use_cooldown_seconds > 0 THEN
    SELECT MAX(used_at) INTO v_last
      FROM public.item_uses
     WHERE user_id = p_user_id AND item_key = p_item_key;
    IF v_last IS NOT NULL AND v_last + make_interval(secs => v_item.use_cooldown_seconds) > now() THEN
      v_wait := CEIL(EXTRACT(EPOCH FROM (v_last + make_interval(secs => v_item.use_cooldown_seconds) - now())));
      RAISE EXCEPTION 'ON_COOLDOWN: % is recharging for another % second(s)', v_item.name, v_wait
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_item.kind = 'pause_potion' THEN
    IF p_context_type IS DISTINCT FROM 'mission_attempt' OR p_context_id IS NULL THEN
      RAISE EXCEPTION 'WRONG_CONTEXT: a Pause Potion only works during a Mission' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_attempt
      FROM public.mission_attempts
     WHERE id = p_context_id AND user_id = p_user_id
       FOR UPDATE;

    IF NOT FOUND OR v_attempt.status <> 'active' OR now() > v_attempt.expires_at THEN
      RAISE EXCEPTION 'NO_ACTIVE_MISSION: there is no running mission to pause' USING ERRCODE = 'P0001';
    END IF;

    SELECT value INTO v_rules FROM public.game_config WHERE key = 'mission_rules';
    v_allowed := LEAST(
      COALESCE((v_item.effect->>'pause_seconds')::INTEGER, 120),
      COALESCE((v_rules->>'pause_max_seconds')::INTEGER, 300) - v_attempt.paused_seconds
    );

    IF v_allowed <= 0 THEN
      RAISE EXCEPTION 'PAUSE_LIMIT: this mission has used all of its pause time' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.mission_attempts
       SET expires_at = expires_at + make_interval(secs => v_allowed),
           paused_seconds = paused_seconds + v_allowed
     WHERE id = p_context_id;

    v_effect := jsonb_build_object(
      'paused_seconds', v_allowed,
      'expires_at', v_attempt.expires_at + make_interval(secs => v_allowed)
    );

  ELSIF v_item.kind = 'streak_restore' THEN
    v_context := 'streak';
    v_day := public.streak_restore_candidate(p_user_id);

    IF v_day IS NULL THEN
      v_max_age := COALESCE(
        (SELECT (value->>'restore_max_age_days')::INTEGER FROM public.game_config WHERE key = 'streak_rules'), 3);
      RAISE EXCEPTION 'NOTHING_TO_RESTORE: a restore covers one missed day in the last % days that would reconnect a streak — there is none right now', v_max_age
        USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.streak_shields (user_id, covered_date, source)
    VALUES (p_user_id, v_day, 'streak_restore');

    v_effect := jsonb_build_object('covered_date', v_day, 'streak', public.compute_streak(p_user_id));

  ELSE
    -- The three Dungeon potions.
    IF p_context_type IS DISTINCT FROM 'dungeon_run' OR p_context_id IS NULL THEN
      RAISE EXCEPTION 'WRONG_CONTEXT: % is used inside a Dungeon', v_item.name USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_run FROM public.dungeon_runs WHERE id = p_context_id AND user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NOT_IN_BATTLE: that is not your Dungeon run' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_battle FROM public.dungeon_battles WHERE id = v_run.battle_id;
    SELECT * INTO v_event FROM public.dungeon_events WHERE id = v_battle.event_id;

    IF v_battle.status NOT IN ('active', 'paused') THEN
      RAISE EXCEPTION 'BATTLE_OVER: this battle is already %', v_battle.status USING ERRCODE = 'P0001';
    END IF;

    -- Each Dungeon decides which potions it allows at all.
    IF NOT COALESCE((v_event.config->'potions'->>v_item.key)::BOOLEAN, TRUE) THEN
      RAISE EXCEPTION 'POTION_DISABLED: % is not allowed in this Dungeon', v_item.name USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_a FROM public.dungeon_assignments
     WHERE run_id = v_run.id AND status = 'active' FOR UPDATE;

    IF v_item.kind = 'revive_potion' THEN
      IF v_run.status <> 'downed' THEN
        RAISE EXCEPTION 'NOT_DOWNED: a Revive Potion is for getting back up' USING ERRCODE = 'P0001';
      END IF;
      v_hp := LEAST(COALESCE((v_item.effect->>'revive_hp')::INTEGER, 50), v_run.combat_hp_max);
      UPDATE public.dungeon_runs
         SET combat_hp = v_hp, status = 'active', downed_at = NULL, last_seen_at = now()
       WHERE id = v_run.id;
      -- Back on your feet with something to do.
      IF NOT EXISTS (SELECT 1 FROM public.dungeon_assignments WHERE run_id = v_run.id AND status = 'active') THEN
        PERFORM public.assign_dungeon_objective(v_battle.id, v_run.id);
      END IF;
      v_effect := jsonb_build_object('revived_to_hp', v_hp);

    ELSE
      -- Health and Rest are between-objectives only: they cannot interrupt a
      -- set that is already being tracked.
      IF v_a.id IS NOT NULL AND v_a.started_at IS NOT NULL THEN
        RAISE EXCEPTION 'MID_OBJECTIVE: finish the set first — potions work between objectives'
          USING ERRCODE = 'P0001';
      END IF;
      IF v_run.status NOT IN ('active', 'disconnected') THEN
        RAISE EXCEPTION 'NOT_FIGHTING: you are % in this battle', v_run.status USING ERRCODE = 'P0001';
      END IF;

      IF v_item.kind = 'health_potion' THEN
        IF v_run.combat_hp >= v_run.combat_hp_max THEN
          RAISE EXCEPTION 'ALREADY_FULL: your combat HP is already full' USING ERRCODE = 'P0001';
        END IF;
        v_heal := COALESCE((v_item.effect->>'heal_hp')::INTEGER, 40);
        v_hp := LEAST(v_run.combat_hp + v_heal, v_run.combat_hp_max);
        UPDATE public.dungeon_runs SET combat_hp = v_hp WHERE id = v_run.id;
        v_effect := jsonb_build_object('healed_to_hp', v_hp, 'healed_by', v_hp - v_run.combat_hp);

      ELSIF v_item.kind = 'rest_potion' THEN
        -- Banked, not applied: see the note at the top of this migration.
        v_extend := COALESCE((v_item.effect->>'extend_seconds')::INTEGER, 60);
        UPDATE public.dungeon_runs
           SET bonus_seconds = bonus_seconds + v_extend
         WHERE id = v_run.id;
        v_effect := jsonb_build_object(
          'banked_seconds', v_extend,
          'bonus_seconds_total', v_run.bonus_seconds + v_extend);

      ELSE
        RAISE EXCEPTION 'UNSUPPORTED_ITEM: % cannot be used yet', v_item.name USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  UPDATE public.user_inventory
     SET quantity = quantity - 1, updated_at = now()
   WHERE user_id = p_user_id AND item_key = p_item_key;

  INSERT INTO public.item_uses (user_id, item_key, context_type, context_id, effect)
  VALUES (p_user_id, p_item_key, v_context, p_context_id, v_effect);

  RETURN jsonb_build_object(
    'success', TRUE, 'item_key', p_item_key, 'remaining', v_qty - 1, 'effect', v_effect
  );
END;
$$;


ALTER FUNCTION "public"."use_item"("p_user_id" "uuid", "p_item_key" "text", "p_context_type" "text", "p_context_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."withdraw_verification_application"("p_application_id" "uuid", "p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_row public.verification_applications%ROWTYPE;
BEGIN
  UPDATE public.verification_applications
     SET status = 'withdrawn', withdrawn_at = clock_timestamp()
   WHERE id = p_application_id AND user_id = p_user_id AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_PENDING: there is no pending application to withdraw';
  END IF;
  RETURN jsonb_build_object('application_id', v_row.id, 'user_id', v_row.user_id, 'status', v_row.status,
                            'evidence_count', v_row.evidence_count);
END;
$$;


ALTER FUNCTION "public"."withdraw_verification_application"("p_application_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."admin_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_user_id" "uuid" NOT NULL,
    "actor_role" "text" NOT NULL,
    "action" "text" NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "admin_audit_log_action_check" CHECK (("action" ~ '^[a-z_]+\.[a-z_]+$'::"text")),
    CONSTRAINT "admin_audit_log_metadata_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "admin_audit_log_target_type_check" CHECK (("target_type" ~ '^[a-z_]+$'::"text"))
);


ALTER TABLE "public"."admin_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_suggestions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "suggestion_text" "text",
    "generated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."ai_suggestions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bosses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "art_key" "text",
    "lore" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."bosses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bug_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "category" "text" DEFAULT 'bug'::"text" NOT NULL,
    "description" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    CONSTRAINT "bug_reports_category_check" CHECK (("category" = ANY (ARRAY['bug'::"text", 'feature_request'::"text", 'other'::"text"]))),
    CONSTRAINT "bug_reports_description_check" CHECK ((("char_length"("description") >= 1) AND ("char_length"("description") <= 1000))),
    CONSTRAINT "bug_reports_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'resolved'::"text", 'dismissed'::"text"])))
);


ALTER TABLE "public"."bug_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "username" "text",
    "rank_badge" "text",
    "message" "text",
    "flagged" boolean DEFAULT false,
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."chat_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."collectibles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "rarity" "text" NOT NULL,
    "gold_value" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "collectibles_gold_value_check" CHECK (("gold_value" >= 0)),
    CONSTRAINT "collectibles_kind_check" CHECK (("kind" = ANY (ARRAY['title'::"text", 'badge'::"text", 'frame'::"text", 'relic'::"text", 'cosmetic'::"text"])))
);


ALTER TABLE "public"."collectibles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commodity_reference_prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "commodity_id" "uuid" NOT NULL,
    "unit" "text" NOT NULL,
    "price_php" numeric(10,2) NOT NULL,
    "region" "text" NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "source" "text" NOT NULL,
    "source_label" "text" NOT NULL,
    "source_reference" "text",
    "source_item" "text" NOT NULL,
    "specification" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "note" "text",
    CONSTRAINT "commodity_reference_prices_price_php_check" CHECK ((("price_php" > (0)::numeric) AND ("price_php" < (100000)::numeric))),
    CONSTRAINT "commodity_reference_prices_region_check" CHECK (("region" = 'NCR'::"text")),
    CONSTRAINT "commodity_reference_prices_source_check" CHECK (("source" = ANY (ARRAY['da_bantay_presyo'::"text", 'admin_adjustment'::"text"]))),
    CONSTRAINT "commodity_reference_prices_source_item_check" CHECK (("char_length"("source_item") > 0)),
    CONSTRAINT "commodity_reference_prices_source_label_check" CHECK (("char_length"("source_label") > 0)),
    CONSTRAINT "reference_price_period" CHECK ((("period_end" >= "period_start") AND (("period_end" - "period_start") <= 13))),
    CONSTRAINT "reference_price_provenance" CHECK (((("source" = 'da_bantay_presyo'::"text") AND ("source_reference" IS NOT NULL) AND ("source_reference" ~ '^https://'::"text")) OR (("source" = 'admin_adjustment'::"text") AND ("note" IS NOT NULL) AND (("char_length"("btrim"("note")) >= 3) AND ("char_length"("btrim"("note")) <= 200)))))
);


ALTER TABLE "public"."commodity_reference_prices" OWNER TO "postgres";


COMMENT ON COLUMN "public"."commodity_reference_prices"."note" IS 'admin_adjustment only: where the price was seen. Required for that source.';



CREATE TABLE IF NOT EXISTS "public"."direct_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "message" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "direct_messages_check" CHECK (("sender_id" <> "recipient_id")),
    CONSTRAINT "direct_messages_message_check" CHECK ((("char_length"("message") >= 1) AND ("char_length"("message") <= 2000)))
);


ALTER TABLE "public"."direct_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dungeon_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "battle_id" "uuid" NOT NULL,
    "run_id" "uuid" NOT NULL,
    "exercise" "text" NOT NULL,
    "target_value" numeric NOT NULL,
    "progress" numeric DEFAULT 0 NOT NULL,
    "base_damage" integer NOT NULL,
    "difficulty" "text" DEFAULT 'medium'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "started_at" timestamp with time zone,
    "deadline_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    CONSTRAINT "dungeon_assignments_base_damage_check" CHECK (("base_damage" > 0)),
    CONSTRAINT "dungeon_assignments_difficulty_check" CHECK (("difficulty" = ANY (ARRAY['easy'::"text", 'medium'::"text", 'hard'::"text"]))),
    CONSTRAINT "dungeon_assignments_progress_check" CHECK (("progress" >= (0)::numeric)),
    CONSTRAINT "dungeon_assignments_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'cleared'::"text", 'failed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "dungeon_assignments_target_value_check" CHECK (("target_value" > (0)::numeric))
);


ALTER TABLE "public"."dungeon_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dungeon_battles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "leader_id" "uuid",
    "status" "text" DEFAULT 'forming'::"text" NOT NULL,
    "seed" bigint NOT NULL,
    "boss_hp" integer NOT NULL,
    "started_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    "last_activity_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "paused_at" timestamp with time zone,
    CONSTRAINT "dungeon_battles_boss_hp_check" CHECK (("boss_hp" >= 0)),
    CONSTRAINT "dungeon_battles_status_check" CHECK (("status" = ANY (ARRAY['forming'::"text", 'active'::"text", 'paused'::"text", 'cleared'::"text", 'wiped'::"text", 'cancelled'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."dungeon_battles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."dungeon_battles"."status" IS 'paused is for a suspected backend outage (every member went silent at once), so an interruption on our side does not fail everybody''s run.';



COMMENT ON COLUMN "public"."dungeon_battles"."paused_at" IS 'Set when every member went silent at once (a suspected outage on our side). Cleared on resume, and every live objective deadline is pushed out by however long it lasted.';



CREATE TABLE IF NOT EXISTS "public"."dungeon_clears" (
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "battle_id" "uuid",
    "contribution_percent" numeric,
    "cleared_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dungeon_clears" OWNER TO "postgres";


COMMENT ON TABLE "public"."dungeon_clears" IS 'One row per player per event: the once-only reward guarantee. A later battle in the same event may be played but pays nothing, and the UI warns before it starts.';



CREATE TABLE IF NOT EXISTS "public"."dungeon_event_invites" (
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "invited_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dungeon_event_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dungeon_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "threat_rank" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "boss_id" "uuid",
    "boss_max_hp" integer NOT NULL,
    "difficulty" "text" DEFAULT 'hard'::"text" NOT NULL,
    "config" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "opens_at" timestamp with time zone,
    "ends_at" timestamp with time zone,
    "created_by" "uuid",
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "dungeon_events_boss_max_hp_check" CHECK (("boss_max_hp" > 0)),
    CONSTRAINT "dungeon_events_check" CHECK ((("ends_at" IS NULL) OR ("opens_at" IS NULL) OR ("ends_at" > "opens_at"))),
    CONSTRAINT "dungeon_events_difficulty_check" CHECK (("difficulty" = ANY (ARRAY['easy'::"text", 'medium'::"text", 'hard'::"text"]))),
    CONSTRAINT "dungeon_events_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'open'::"text", 'closed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."dungeon_events" OWNER TO "postgres";


COMMENT ON COLUMN "public"."dungeon_events"."config" IS 'Per-event rules that override game_config: which potions are allowed, party cap, minimum contribution, the exercise/objective pool and difficulty.';



COMMENT ON COLUMN "public"."dungeon_events"."created_by" IS 'SET NULL rather than CASCADE: an event outlives the admin account that opened it, or deleting an admin would delete other players'' clears.';



CREATE TABLE IF NOT EXISTS "public"."dungeon_objective_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "assignment_id" "uuid" NOT NULL,
    "actor_run_id" "uuid" NOT NULL,
    "workout_log_id" "uuid",
    "achieved_value" numeric NOT NULL,
    "form_quality" numeric,
    "damage" integer DEFAULT 0 NOT NULL,
    "is_assist" boolean DEFAULT false NOT NULL,
    "is_crit" boolean DEFAULT false NOT NULL,
    "elapsed_seconds" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "dungeon_objective_results_achieved_value_check" CHECK (("achieved_value" >= (0)::numeric)),
    CONSTRAINT "dungeon_objective_results_damage_check" CHECK (("damage" >= 0)),
    CONSTRAINT "dungeon_objective_results_elapsed_seconds_check" CHECK ((("elapsed_seconds" IS NULL) OR ("elapsed_seconds" >= 0))),
    CONSTRAINT "dungeon_objective_results_form_quality_check" CHECK ((("form_quality" IS NULL) OR (("form_quality" >= (0)::numeric) AND ("form_quality" <= (1)::numeric))))
);


ALTER TABLE "public"."dungeon_objective_results" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dungeon_reward_pool" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "collectible_id" "uuid",
    "gold_amount" integer,
    "weight" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "dungeon_reward_pool_check" CHECK ((("collectible_id" IS NOT NULL) OR ("gold_amount" IS NOT NULL))),
    CONSTRAINT "dungeon_reward_pool_gold_amount_check" CHECK ((("gold_amount" IS NULL) OR ("gold_amount" > 0))),
    CONSTRAINT "dungeon_reward_pool_weight_check" CHECK (("weight" > 0))
);


ALTER TABLE "public"."dungeon_reward_pool" OWNER TO "postgres";


COMMENT ON TABLE "public"."dungeon_reward_pool" IS 'What an event can drop, with weights. Rolls happen server-side inside the settling transaction; the client never generates a reward.';



CREATE TABLE IF NOT EXISTS "public"."dungeon_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "battle_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'joined'::"text" NOT NULL,
    "combat_hp" integer NOT NULL,
    "combat_hp_max" integer NOT NULL,
    "total_damage" integer DEFAULT 0 NOT NULL,
    "contribution_percent" numeric,
    "reward_eligible" boolean,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "downed_at" timestamp with time zone,
    "bonus_seconds" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "dungeon_runs_bonus_seconds_check" CHECK (("bonus_seconds" >= 0)),
    CONSTRAINT "dungeon_runs_combat_hp_check" CHECK (("combat_hp" >= 0)),
    CONSTRAINT "dungeon_runs_combat_hp_max_check" CHECK (("combat_hp_max" > 0)),
    CONSTRAINT "dungeon_runs_status_check" CHECK (("status" = ANY (ARRAY['joined'::"text", 'ready'::"text", 'active'::"text", 'disconnected'::"text", 'downed'::"text", 'out'::"text", 'quit'::"text", 'failed'::"text", 'cleared'::"text"]))),
    CONSTRAINT "dungeon_runs_total_damage_check" CHECK (("total_damage" >= 0))
);


ALTER TABLE "public"."dungeon_runs" OWNER TO "postgres";


COMMENT ON COLUMN "public"."dungeon_runs"."combat_hp" IS 'RPG combat HP for this fight, standardised at join time. Not a real-world health measure of any kind.';



COMMENT ON COLUMN "public"."dungeon_runs"."last_seen_at" IS 'Server-stamped on every state poll. The disconnect window is measured from here, never from a client timer.';



COMMENT ON COLUMN "public"."dungeon_runs"."downed_at" IS 'Server-stamped when combat HP hit 0. Cleared on revive. The revive window is measured from here, and a run past it becomes out.';



COMMENT ON COLUMN "public"."dungeon_runs"."bonus_seconds" IS 'Objective time bought with a Rest Potion between objectives, spent by the next start_dungeon_objective. Banked rather than applied live, because a potion may never interrupt a tracked set.';



CREATE TABLE IF NOT EXISTS "public"."exercise_library" (
    "exercise" "text" NOT NULL,
    "source" "text" DEFAULT 'repdb'::"text" NOT NULL,
    "source_id" "text" NOT NULL,
    "name_en" "text" NOT NULL,
    "description_en" "text",
    "difficulty" "text",
    "equipment" "text",
    "body_part" "text",
    "primary_muscles" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "secondary_muscles" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "tags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "instructions_en" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "tips_en" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "image_start" "text",
    "image_peak" "text",
    "imported_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "exercise_library_difficulty_check" CHECK (("difficulty" = ANY (ARRAY['beginner'::"text", 'intermediate'::"text", 'advanced'::"text"]))),
    CONSTRAINT "exercise_library_source_check" CHECK (("source" = 'repdb'::"text"))
);


ALTER TABLE "public"."exercise_library" OWNER TO "postgres";


COMMENT ON TABLE "public"."exercise_library" IS 'Exercise data by RepDB (repdb.co), free-tier licence: only the exercises mapped in _shared/planCatalog.ts, shown only inside the app, attribution in Credits + README. Not user data.';



CREATE TABLE IF NOT EXISTS "public"."exercises" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "primary_attribute" "text",
    "metric_type" "text" DEFAULT 'reps'::"text" NOT NULL,
    CONSTRAINT "exercises_metric_type_check" CHECK (("metric_type" = ANY (ARRAY['reps'::"text", 'duration'::"text", 'distance'::"text"]))),
    CONSTRAINT "exercises_primary_attribute_check" CHECK (("primary_attribute" = ANY (ARRAY['strength'::"text", 'agility'::"text", 'vitality'::"text"])))
);


ALTER TABLE "public"."exercises" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fitrack_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "logged_method" "text" NOT NULL,
    "image_url" "text",
    "food_name" "text" NOT NULL,
    "weight_g" numeric NOT NULL,
    "calories" numeric NOT NULL,
    "protein" numeric NOT NULL,
    "carbs" numeric NOT NULL,
    "fat" numeric NOT NULL,
    "meal_period" "text" NOT NULL,
    "logged_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fiber" numeric(6,2) DEFAULT 0 NOT NULL,
    "sugar" numeric DEFAULT 0 NOT NULL,
    "food_id" "uuid",
    "usda_fdc_id" integer,
    "nutrition_source" "text" DEFAULT 'user_entered'::"text" NOT NULL,
    "is_estimate" boolean,
    "nutrition_snapshot" "jsonb",
    CONSTRAINT "fitrack_logs_fiber_check" CHECK ((("fiber" >= (0)::numeric) AND ("fiber" <= (2000)::numeric))),
    CONSTRAINT "fitrack_logs_logged_method_check" CHECK (("logged_method" = ANY (ARRAY['ai_scan'::"text", 'manual_scale'::"text", 'manual_entry'::"text"]))),
    CONSTRAINT "fitrack_logs_meal_period_check" CHECK (("meal_period" = ANY (ARRAY['Breakfast'::"text", 'Lunch'::"text", 'Dinner'::"text", 'Snack'::"text"]))),
    CONSTRAINT "fitrack_logs_no_image_url" CHECK (("image_url" IS NULL)),
    CONSTRAINT "fitrack_logs_nutrition_source_check" CHECK (("nutrition_source" = ANY (ARRAY['local_food'::"text", 'usda'::"text", 'user_edited'::"text", 'user_entered'::"text"]))),
    CONSTRAINT "fitrack_logs_sugar_check" CHECK ((("sugar" >= (0)::numeric) AND ("sugar" <= (2000)::numeric))),
    CONSTRAINT "fitrack_logs_usda_fdc_id_check" CHECK (("usda_fdc_id" > 0))
);


ALTER TABLE "public"."fitrack_logs" OWNER TO "postgres";


COMMENT ON COLUMN "public"."fitrack_logs"."nutrition_source" IS 'Decided server-side by log_meal_entry: local_food / usda (values match that record), user_edited (a record was chosen but values were changed), user_entered (no record).';



COMMENT ON COLUMN "public"."fitrack_logs"."is_estimate" IS 'TRUE when the values came unedited from an estimated food record, FALSE for unedited USDA data, NULL when the user supplied or edited the values.';



COMMENT ON COLUMN "public"."fitrack_logs"."nutrition_snapshot" IS 'The food/USDA record, per-100 g values and provenance exactly as they were when logged. Never updated.';



CREATE TABLE IF NOT EXISTS "public"."food_servings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "food_id" "uuid" NOT NULL,
    "label" "text" NOT NULL,
    "grams" numeric(7,1) NOT NULL,
    "is_estimate" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "food_servings_grams_check" CHECK ((("grams" > (0)::numeric) AND ("grams" <= (2000)::numeric))),
    CONSTRAINT "food_servings_label_check" CHECK ((("char_length"("label") >= 1) AND ("char_length"("label") <= 60)))
);


ALTER TABLE "public"."food_servings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."foods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "local_names" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "aliases" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "category" "text" NOT NULL,
    "region" "text" NOT NULL,
    "preparation" "text",
    "brand" "text",
    "calories" numeric(7,1) NOT NULL,
    "protein" numeric(6,1) NOT NULL,
    "carbs" numeric(6,1) NOT NULL,
    "fat" numeric(6,1) NOT NULL,
    "fiber" numeric(6,1),
    "sugar" numeric(6,1),
    "source" "text" NOT NULL,
    "source_reference" "text" NOT NULL,
    "is_estimate" boolean NOT NULL,
    "estimate_note" "text",
    "active" boolean DEFAULT true NOT NULL,
    "search_text" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "description" "text",
    CONSTRAINT "foods_branded_has_brand" CHECK ((("category" <> 'branded'::"text") OR ("brand" IS NOT NULL))),
    CONSTRAINT "foods_calories_check" CHECK ((("calories" >= (0)::numeric) AND ("calories" <= (900)::numeric))),
    CONSTRAINT "foods_carbs_check" CHECK ((("carbs" >= (0)::numeric) AND ("carbs" <= (100)::numeric))),
    CONSTRAINT "foods_category_check" CHECK (("category" = ANY (ARRAY['generic'::"text", 'branded'::"text", 'ingredient'::"text", 'prepared_meal'::"text"]))),
    CONSTRAINT "foods_description_length" CHECK ((("description" IS NULL) OR (("char_length"("description") >= 1) AND ("char_length"("description") <= 500)))),
    CONSTRAINT "foods_estimate_explained" CHECK (((NOT "is_estimate") OR (("estimate_note" IS NOT NULL) AND ("char_length"("estimate_note") > 0)))),
    CONSTRAINT "foods_estimate_sources" CHECK ((("source" <> ALL (ARRAY['manual_estimate'::"text", 'usda_derived'::"text"])) OR "is_estimate")),
    CONSTRAINT "foods_fat_check" CHECK ((("fat" >= (0)::numeric) AND ("fat" <= (100)::numeric))),
    CONSTRAINT "foods_fiber_check" CHECK ((("fiber" >= (0)::numeric) AND ("fiber" <= (100)::numeric))),
    CONSTRAINT "foods_macros_fit" CHECK (((("protein" + "carbs") + "fat") <= (101)::numeric)),
    CONSTRAINT "foods_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120))),
    CONSTRAINT "foods_preparation_check" CHECK (("preparation" = ANY (ARRAY['raw'::"text", 'boiled'::"text", 'fried'::"text", 'grilled'::"text", 'steamed'::"text", 'stewed'::"text", 'baked'::"text", 'dried'::"text", 'canned'::"text", 'cooked'::"text"]))),
    CONSTRAINT "foods_protein_check" CHECK ((("protein" >= (0)::numeric) AND ("protein" <= (100)::numeric))),
    CONSTRAINT "foods_region_check" CHECK (("region" = ANY (ARRAY['ph'::"text", 'asia'::"text", 'international'::"text"]))),
    CONSTRAINT "foods_slug_check" CHECK (("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text")),
    CONSTRAINT "foods_source_check" CHECK (("source" = ANY (ARRAY['usda_derived'::"text", 'usda'::"text", 'philfct'::"text", 'label'::"text", 'manual_estimate'::"text"]))),
    CONSTRAINT "foods_source_reference_check" CHECK (("char_length"("source_reference") > 0)),
    CONSTRAINT "foods_sugar_check" CHECK ((("sugar" >= (0)::numeric) AND ("sugar" <= (100)::numeric))),
    CONSTRAINT "foods_sugar_within_carbs" CHECK ((("sugar" IS NULL) OR ("sugar" <= ("carbs" + 0.5))))
);


ALTER TABLE "public"."foods" OWNER TO "postgres";


COMMENT ON TABLE "public"."foods" IS 'Local food records with nutrition per 100 g and its provenance. Seeded by migration; since 2026-09-18 admins add and edit foods through the admin-foods function (audited in admin_audit_log). See docs/nutrition/food-data-sources.md.';



COMMENT ON COLUMN "public"."foods"."description" IS 'Short admin-written description shown when the food is picked in Log Meal. Not nutrition data.';



CREATE TABLE IF NOT EXISTS "public"."friendships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requester_id" "uuid" NOT NULL,
    "addressee_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    CONSTRAINT "friendships_check" CHECK (("requester_id" <> "addressee_id")),
    CONSTRAINT "friendships_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text"])))
);


ALTER TABLE "public"."friendships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."game_config" (
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL,
    "description" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."game_config" OWNER TO "postgres";


COMMENT ON TABLE "public"."game_config" IS 'Tunable gameplay numbers (combat, timers, economy). Nothing in the app may hardcode these. Server-side reads only; no RLS policies, so only the service role can see it.';



CREATE TABLE IF NOT EXISTS "public"."gold_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "amount" integer NOT NULL,
    "reason" "text" NOT NULL,
    "source_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "idempotency_key" "text",
    CONSTRAINT "gold_ledger_amount_nonzero" CHECK (("amount" <> 0)),
    CONSTRAINT "gold_ledger_reason_check" CHECK (("reason" = ANY (ARRAY['daily_meal_log'::"text", 'daily_community_post'::"text", 'mission_first_clear'::"text", 'dungeon_clear'::"text", 'dungeon_duplicate_compensation'::"text", 'dungeon_consolation'::"text", 'shop_purchase'::"text", 'admin_adjustment'::"text"])))
);


ALTER TABLE "public"."gold_ledger" OWNER TO "postgres";


COMMENT ON COLUMN "public"."gold_ledger"."idempotency_key" IS 'Caller-supplied natural key for an award or spend (e.g. daily_meal_log:<user>:<local date>, mission:<mission id>:<user id>). The unique index on it is what makes paying twice impossible, instead of a read-then-write check that can race.';



CREATE TABLE IF NOT EXISTS "public"."gymmunity_posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "tab" "text" NOT NULL,
    "content" "text" NOT NULL,
    "image_url" "text",
    "status" "text" DEFAULT 'approved'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "title" "text",
    "ingredients" "text",
    "calories" numeric(7,2),
    "protein" numeric(6,2),
    "carbs" numeric(6,2),
    "fat" numeric(6,2),
    CONSTRAINT "gymmunity_posts_calories_check" CHECK ((("calories" >= (0)::numeric) AND ("calories" <= (10000)::numeric))),
    CONSTRAINT "gymmunity_posts_carbs_check" CHECK ((("carbs" >= (0)::numeric) AND ("carbs" <= (2000)::numeric))),
    CONSTRAINT "gymmunity_posts_fat_check" CHECK ((("fat" >= (0)::numeric) AND ("fat" <= (2000)::numeric))),
    CONSTRAINT "gymmunity_posts_food_requires_nutrients" CHECK ((("tab" <> 'food'::"text") OR (("calories" IS NOT NULL) AND ("protein" IS NOT NULL) AND ("carbs" IS NOT NULL) AND ("fat" IS NOT NULL)))),
    CONSTRAINT "gymmunity_posts_ingredients_check" CHECK (("char_length"("ingredients") <= 1000)),
    CONSTRAINT "gymmunity_posts_protein_check" CHECK ((("protein" >= (0)::numeric) AND ("protein" <= (2000)::numeric))),
    CONSTRAINT "gymmunity_posts_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "gymmunity_posts_tab_check" CHECK (("tab" = ANY (ARRAY['fitness'::"text", 'food'::"text"]))),
    CONSTRAINT "gymmunity_posts_title_check" CHECK (("char_length"("title") <= 100))
);


ALTER TABLE "public"."gymmunity_posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."item_uses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "item_key" "text" NOT NULL,
    "context_type" "text",
    "context_id" "uuid",
    "effect" "jsonb",
    "used_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "item_uses_context_type_check" CHECK (("context_type" = ANY (ARRAY['mission_attempt'::"text", 'dungeon_run'::"text", 'streak'::"text"])))
);


ALTER TABLE "public"."item_uses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."market_commodities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "local_names" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "commodity_group" "text" NOT NULL,
    "purchase_unit" "text" NOT NULL,
    "grams_per_piece" numeric(6,1),
    "grams_per_piece_source" "text",
    "food_id" "uuid",
    "inedible_share" numeric(4,3),
    "inedible_share_source" "text",
    "calculation_note" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commodity_inedible_share_sourced" CHECK (((("inedible_share" IS NULL) = ("inedible_share_source" IS NULL)) AND (("inedible_share" IS NULL) OR ("food_id" IS NOT NULL)))),
    CONSTRAINT "commodity_piece_weight" CHECK (((("purchase_unit" = 'piece'::"text") = ("grams_per_piece" IS NOT NULL)) AND (("grams_per_piece" IS NULL) = ("grams_per_piece_source" IS NULL)))),
    CONSTRAINT "market_commodities_calculation_note_check" CHECK (("char_length"("calculation_note") > 0)),
    CONSTRAINT "market_commodities_commodity_group_check" CHECK (("commodity_group" = ANY (ARRAY['animal_protein'::"text", 'plant_protein'::"text", 'staple'::"text"]))),
    CONSTRAINT "market_commodities_grams_per_piece_check" CHECK ((("grams_per_piece" > (0)::numeric) AND ("grams_per_piece" <= (5000)::numeric))),
    CONSTRAINT "market_commodities_inedible_share_check" CHECK ((("inedible_share" >= (0)::numeric) AND ("inedible_share" < (1)::numeric))),
    CONSTRAINT "market_commodities_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120))),
    CONSTRAINT "market_commodities_purchase_unit_check" CHECK (("purchase_unit" = ANY (ARRAY['kg'::"text", 'piece'::"text"]))),
    CONSTRAINT "market_commodities_slug_check" CHECK (("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))
);


ALTER TABLE "public"."market_commodities" OWNER TO "postgres";


COMMENT ON TABLE "public"."market_commodities" IS 'Items as bought at the market, with a nutrition basis and — only when sourced — an inedible share. Maintained by migration. See docs/nutrition/price-data-sources.md.';



CREATE TABLE IF NOT EXISTS "public"."mission_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "is_replay" boolean DEFAULT false NOT NULL,
    "current_sequence" integer DEFAULT 1 NOT NULL,
    "boss_hp" integer NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "paused_seconds" integer DEFAULT 0 NOT NULL,
    "objective_started_at" timestamp with time zone,
    "ended_at" timestamp with time zone,
    CONSTRAINT "mission_attempts_boss_hp_check" CHECK (("boss_hp" >= 0)),
    CONSTRAINT "mission_attempts_current_sequence_check" CHECK (("current_sequence" > 0)),
    CONSTRAINT "mission_attempts_paused_seconds_check" CHECK (("paused_seconds" >= 0)),
    CONSTRAINT "mission_attempts_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'failed'::"text", 'abandoned'::"text"])))
);


ALTER TABLE "public"."mission_attempts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."mission_attempts"."objective_started_at" IS 'Server-stamped when tracking actually goes live for the current objective, not when the camera opens. Reference-rep calibration and repositioning the phone must not burn the clock, and this is also the baseline every plausibility check measures against.';



CREATE TABLE IF NOT EXISTS "public"."mission_chapters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "number" integer NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "mission_chapters_number_check" CHECK (("number" > 0))
);


ALTER TABLE "public"."mission_chapters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mission_clears" (
    "user_id" "uuid" NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "attempt_id" "uuid",
    "grade" "text",
    "cleared_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mission_clears" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mission_objective_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attempt_id" "uuid" NOT NULL,
    "objective_id" "uuid" NOT NULL,
    "workout_log_id" "uuid",
    "achieved_value" numeric NOT NULL,
    "form_quality" numeric,
    "damage" integer DEFAULT 0 NOT NULL,
    "is_crit" boolean DEFAULT false NOT NULL,
    "success" boolean NOT NULL,
    "elapsed_seconds" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "mission_objective_results_achieved_value_check" CHECK (("achieved_value" >= (0)::numeric)),
    CONSTRAINT "mission_objective_results_damage_check" CHECK (("damage" >= 0)),
    CONSTRAINT "mission_objective_results_elapsed_seconds_check" CHECK ((("elapsed_seconds" IS NULL) OR ("elapsed_seconds" >= 0))),
    CONSTRAINT "mission_objective_results_form_quality_check" CHECK ((("form_quality" IS NULL) OR (("form_quality" >= (0)::numeric) AND ("form_quality" <= (1)::numeric))))
);


ALTER TABLE "public"."mission_objective_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."mission_objective_results" IS 'One row per objective per attempt. The unique constraint makes a resubmitted objective a no-op instead of double damage, and workout_log_id ties the damage back to the real workout it came from.';



CREATE TABLE IF NOT EXISTS "public"."mission_objectives" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "sequence" integer NOT NULL,
    "exercise" "text" NOT NULL,
    "target_value" numeric NOT NULL,
    "objective_time_limit_seconds" integer,
    "base_damage" integer NOT NULL,
    CONSTRAINT "mission_objectives_base_damage_check" CHECK (("base_damage" > 0)),
    CONSTRAINT "mission_objectives_objective_time_limit_seconds_check" CHECK ((("objective_time_limit_seconds" IS NULL) OR ("objective_time_limit_seconds" > 0))),
    CONSTRAINT "mission_objectives_sequence_check" CHECK (("sequence" > 0)),
    CONSTRAINT "mission_objectives_target_value_check" CHECK (("target_value" > (0)::numeric))
);


ALTER TABLE "public"."mission_objectives" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."missions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "chapter_id" "uuid" NOT NULL,
    "level_number" integer NOT NULL,
    "name" "text" NOT NULL,
    "boss_id" "uuid",
    "rank" "text",
    "max_hp" integer NOT NULL,
    "time_limit_seconds" integer NOT NULL,
    "difficulty" "text" DEFAULT 'medium'::"text" NOT NULL,
    "is_boss_level" boolean DEFAULT false NOT NULL,
    "reward_xp" integer DEFAULT 0 NOT NULL,
    "reward_gold" integer DEFAULT 0 NOT NULL,
    "reward_collectible_id" "uuid",
    "is_active" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "missions_difficulty_check" CHECK (("difficulty" = ANY (ARRAY['easy'::"text", 'medium'::"text", 'hard'::"text"]))),
    CONSTRAINT "missions_level_number_check" CHECK (("level_number" > 0)),
    CONSTRAINT "missions_max_hp_check" CHECK (("max_hp" > 0)),
    CONSTRAINT "missions_reward_gold_check" CHECK (("reward_gold" >= 0)),
    CONSTRAINT "missions_reward_xp_check" CHECK (("reward_xp" >= 0)),
    CONSTRAINT "missions_time_limit_seconds_check" CHECK ((("time_limit_seconds" >= 60) AND ("time_limit_seconds" <= 21600)))
);


ALTER TABLE "public"."missions" OWNER TO "postgres";


COMMENT ON COLUMN "public"."missions"."is_active" IS 'A mission is built inactive and then published. Publishing is what validates that its boss HP is actually reachable — see assert_mission_is_clearable().';



CREATE TABLE IF NOT EXISTS "public"."privacy_export_coverage" (
    "table_name" "text" NOT NULL,
    "column_name" "text" NOT NULL,
    "status" "text" NOT NULL,
    "reason" "text" NOT NULL,
    CONSTRAINT "privacy_export_coverage_reason_check" CHECK (("char_length"("reason") > 0)),
    CONSTRAINT "privacy_export_coverage_status_check" CHECK (("status" = ANY (ARRAY['exported'::"text", 'excluded'::"text"])))
);


ALTER TABLE "public"."privacy_export_coverage" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."privacy_notices" (
    "consent_type" "text" NOT NULL,
    "version" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "is_draft" boolean NOT NULL,
    "published_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "privacy_notices_body_check" CHECK (("char_length"("body") > 0)),
    CONSTRAINT "privacy_notices_consent_type_check" CHECK (("consent_type" = ANY (ARRAY['privacy_notice'::"text", 'camera'::"text", 'gps'::"text", 'ai_features'::"text", 'relative_leaderboard'::"text", 'verification'::"text", 'training_limits'::"text"]))),
    CONSTRAINT "privacy_notices_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 120))),
    CONSTRAINT "privacy_notices_version_check" CHECK (("version" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[a-z0-9-]+$'::"text"))
);


ALTER TABLE "public"."privacy_notices" OWNER TO "postgres";


COMMENT ON TABLE "public"."privacy_notices" IS 'Versioned notice texts. Never edited: publish a new version. The newest published_at per type is current.';



CREATE TABLE IF NOT EXISTS "public"."rank_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "old_rank" "text",
    "new_rank" "text",
    "achieved_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."rank_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rank_thresholds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rank_name" "text" NOT NULL,
    "focus_type" "text" NOT NULL,
    "min_xp" integer NOT NULL,
    "tier_index" integer NOT NULL,
    "sub_ranks" integer DEFAULT 5 NOT NULL,
    "sub_rank_span_xp" integer
);


ALTER TABLE "public"."rank_thresholds" OWNER TO "postgres";


COMMENT ON COLUMN "public"."rank_thresholds"."sub_ranks" IS 'How many sub-ranks this tier divides into by interpolation. Top tier (Monarch) uses 10.';



COMMENT ON COLUMN "public"."rank_thresholds"."sub_rank_span_xp" IS 'Top tier only: XP per sub-rank band, since there is no next threshold to interpolate against.';



CREATE TABLE IF NOT EXISTS "public"."rarities" (
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer NOT NULL,
    "color" "text" NOT NULL
);


ALTER TABLE "public"."rarities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rate_limits" (
    "user_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "window_start" timestamp with time zone DEFAULT "now"() NOT NULL,
    "count" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."rate_limits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routine_exercises" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "routine_id" "uuid" NOT NULL,
    "exercise" "text" NOT NULL,
    "position" integer NOT NULL,
    "target_sets" integer,
    "target_reps" integer,
    "target_duration_seconds" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."routine_exercises" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."routines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_items" (
    "key" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "price_gold" integer NOT NULL,
    "max_stack" integer DEFAULT 1 NOT NULL,
    "purchase_cooldown_seconds" integer DEFAULT 0 NOT NULL,
    "use_cooldown_seconds" integer DEFAULT 0 NOT NULL,
    "scope" "text" NOT NULL,
    "effect" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "shop_items_kind_check" CHECK (("kind" = ANY (ARRAY['health_potion'::"text", 'revive_potion'::"text", 'pause_potion'::"text", 'rest_potion'::"text", 'streak_restore'::"text"]))),
    CONSTRAINT "shop_items_max_stack_check" CHECK (("max_stack" > 0)),
    CONSTRAINT "shop_items_price_gold_check" CHECK (("price_gold" > 0)),
    CONSTRAINT "shop_items_purchase_cooldown_seconds_check" CHECK (("purchase_cooldown_seconds" >= 0)),
    CONSTRAINT "shop_items_scope_check" CHECK (("scope" = ANY (ARRAY['mission'::"text", 'dungeon'::"text", 'global'::"text"]))),
    CONSTRAINT "shop_items_use_cooldown_seconds_check" CHECK (("use_cooldown_seconds" >= 0))
);


ALTER TABLE "public"."shop_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_purchases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "item_key" "text" NOT NULL,
    "quantity" integer NOT NULL,
    "price_total" integer NOT NULL,
    "ledger_id" "uuid",
    "request_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "shop_purchases_price_total_check" CHECK (("price_total" > 0)),
    CONSTRAINT "shop_purchases_quantity_check" CHECK (("quantity" > 0))
);


ALTER TABLE "public"."shop_purchases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."specialization_affinity" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "focus_type" "text" NOT NULL,
    "match_type" "text" NOT NULL,
    "match_value" "text" NOT NULL,
    "multiplier" numeric(4,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "specialization_affinity_match_type_check" CHECK (("match_type" = ANY (ARRAY['exercise'::"text", 'attribute'::"text"]))),
    CONSTRAINT "specialization_affinity_multiplier_check" CHECK ((("multiplier" > (0)::numeric) AND ("multiplier" <= (3)::numeric)))
);


ALTER TABLE "public"."specialization_affinity" OWNER TO "postgres";


COMMENT ON TABLE "public"."specialization_affinity" IS 'Per-specialization XP multipliers. Absent row means 1.0. Exercise rows beat attribute rows.';



CREATE TABLE IF NOT EXISTS "public"."streak_shields" (
    "user_id" "uuid" NOT NULL,
    "covered_date" "date" NOT NULL,
    "source" "text" DEFAULT 'streak_restore'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "streak_shields_source_check" CHECK (("source" = ANY (ARRAY['streak_restore'::"text", 'admin_grant'::"text"])))
);


ALTER TABLE "public"."streak_shields" OWNER TO "postgres";


COMMENT ON TABLE "public"."streak_shields" IS 'Days that count as trained without a workout, bought with a Streak Restore. The primary key means the same day can never be shielded twice.';



CREATE TABLE IF NOT EXISTS "public"."strength_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "workout_log_id" "uuid",
    "exercise" "text" NOT NULL,
    "weight_kg" numeric(6,2) NOT NULL,
    "reps" integer NOT NULL,
    "e1rm_kg" numeric(6,2) NOT NULL,
    "formula" "text" DEFAULT 'epley'::"text" NOT NULL,
    "bodyweight_kg" numeric(5,2),
    "relative_e1rm" numeric(6,3),
    "workout_source" "text" NOT NULL,
    "rep_quality_score" numeric(4,3),
    "form_verified" boolean DEFAULT false NOT NULL,
    "achieved_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "strength_records_bodyweight_kg_check" CHECK ((("bodyweight_kg" IS NULL) OR (("bodyweight_kg" > (0)::numeric) AND ("bodyweight_kg" < (500)::numeric)))),
    CONSTRAINT "strength_records_e1rm_kg_check" CHECK (("e1rm_kg" > (0)::numeric)),
    CONSTRAINT "strength_records_reps_check" CHECK ((("reps" >= 1) AND ("reps" <= 12))),
    CONSTRAINT "strength_records_weight_kg_check" CHECK ((("weight_kg" > (0)::numeric) AND ("weight_kg" <= (500)::numeric))),
    CONSTRAINT "strength_records_workout_source_check" CHECK (("workout_source" = ANY (ARRAY['camera'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."strength_records" OWNER TO "postgres";


COMMENT ON COLUMN "public"."strength_records"."form_verified" IS 'Camera-observed movement at or above the quality threshold. Says nothing about the load, which is always user-entered.';



CREATE OR REPLACE VIEW "public"."strength_prs" WITH ("security_invoker"='on') AS
 SELECT DISTINCT ON ("user_id", "exercise") "user_id",
    "exercise",
    "id" AS "record_id",
    "weight_kg",
    "reps",
    "e1rm_kg",
    "relative_e1rm",
    "bodyweight_kg",
    "form_verified",
    "workout_source",
    "achieved_at"
   FROM "public"."strength_records"
  ORDER BY "user_id", "exercise", "e1rm_kg" DESC, "achieved_at";


ALTER VIEW "public"."strength_prs" OWNER TO "postgres";


COMMENT ON VIEW "public"."strength_prs" IS 'Best e1RM per user per exercise. Ties break toward the EARLIER lift, so a repeated best keeps its original date.';



CREATE TABLE IF NOT EXISTS "public"."threat_ranks" (
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer NOT NULL,
    "is_anomalous" boolean DEFAULT false NOT NULL,
    "properties" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."threat_ranks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."training_limits" (
    "user_id" "uuid" NOT NULL,
    "areas" "text"[] NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "training_limits_areas_check" CHECK (((("cardinality"("areas") >= 1) AND ("cardinality"("areas") <= 3)) AND ("areas" <@ ARRAY['knees'::"text", 'lower_back'::"text", 'shoulders'::"text"])))
);


ALTER TABLE "public"."training_limits" OWNER TO "postgres";


COMMENT ON TABLE "public"."training_limits" IS 'Areas to go easy on — health information. Stored only while the training_limits opt-in is granted (set_training_limits); deleted on withdrawal. Never sent to AI.';



CREATE TABLE IF NOT EXISTS "public"."training_plan_days" (
    "plan_id" "uuid" NOT NULL,
    "day" "date" NOT NULL,
    "session_key" "text",
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "status_at" timestamp with time zone,
    CONSTRAINT "training_plan_days_rest_is_planned" CHECK ((("session_key" IS NOT NULL) OR ("status" = 'planned'::"text"))),
    CONSTRAINT "training_plan_days_session_key_check" CHECK ((("session_key" IS NULL) OR ("session_key" ~ '^[A-F]$'::"text"))),
    CONSTRAINT "training_plan_days_status_check" CHECK (("status" = ANY (ARRAY['planned'::"text", 'done'::"text", 'skipped'::"text"])))
);


ALTER TABLE "public"."training_plan_days" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."training_plan_feedback" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "day" "date",
    "session_key" "text" NOT NULL,
    "rating" "text" NOT NULL,
    "level_before" integer NOT NULL,
    "level_after" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "training_plan_feedback_level_after_check" CHECK ((("level_after" >= '-3'::integer) AND ("level_after" <= 3))),
    CONSTRAINT "training_plan_feedback_level_before_check" CHECK ((("level_before" >= '-3'::integer) AND ("level_before" <= 3))),
    CONSTRAINT "training_plan_feedback_rating_check" CHECK (("rating" = ANY (ARRAY['too_easy'::"text", 'just_right'::"text", 'too_hard'::"text"]))),
    CONSTRAINT "training_plan_feedback_session_key_check" CHECK (("session_key" ~ '^[A-F]$'::"text"))
);


ALTER TABLE "public"."training_plan_feedback" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."training_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "generator_version" integer NOT NULL,
    "difficulty_step" integer DEFAULT 0 NOT NULL,
    "sessions" "jsonb" NOT NULL,
    "notes" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "training_plans_dates" CHECK (("end_date" >= "start_date")),
    CONSTRAINT "training_plans_difficulty_step_check" CHECK ((("difficulty_step" >= 0) AND ("difficulty_step" <= 3))),
    CONSTRAINT "training_plans_generator_version_check" CHECK (("generator_version" > 0)),
    CONSTRAINT "training_plans_notes_check" CHECK (("jsonb_typeof"("notes") = 'array'::"text")),
    CONSTRAINT "training_plans_sessions_check" CHECK ((("jsonb_typeof"("sessions") = 'array'::"text") AND (("jsonb_array_length"("sessions") >= 1) AND ("jsonb_array_length"("sessions") <= 6)))),
    CONSTRAINT "training_plans_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'replaced'::"text", 'finished'::"text"])))
);


ALTER TABLE "public"."training_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."training_surveys" (
    "user_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "answers" "jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "training_surveys_answers_check" CHECK ((("answers" IS NULL) OR ("jsonb_typeof"("answers") = 'object'::"text"))),
    CONSTRAINT "training_surveys_answers_when_completed" CHECK ((("status" = 'completed'::"text") = ("answers" IS NOT NULL))),
    CONSTRAINT "training_surveys_status_check" CHECK (("status" = ANY (ARRAY['completed'::"text", 'skipped'::"text"])))
);


ALTER TABLE "public"."training_surveys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_budget_settings" (
    "user_id" "uuid" NOT NULL,
    "daily_budget_php" numeric(10,2) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_budget_settings_daily_budget_php_check" CHECK ((("daily_budget_php" > (0)::numeric) AND ("daily_budget_php" <= (100000)::numeric)))
);


ALTER TABLE "public"."user_budget_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_collectibles" (
    "user_id" "uuid" NOT NULL,
    "collectible_id" "uuid" NOT NULL,
    "source_type" "text",
    "source_id" "uuid",
    "equipped" boolean DEFAULT false NOT NULL,
    "acquired_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_collectibles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_collectibles" IS 'What each player owns. The primary key is also the duplicate detector: a reward roll that conflicts here is swapped for an alternative plus gold compensation.';



CREATE TABLE IF NOT EXISTS "public"."user_commodity_prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "commodity_id" "uuid" NOT NULL,
    "unit" "text" NOT NULL,
    "price_php" numeric(10,2),
    "entered_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "user_commodity_prices_price_php_check" CHECK ((("price_php" > (0)::numeric) AND ("price_php" <= (100000)::numeric)))
);


ALTER TABLE "public"."user_commodity_prices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_consents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "consent_type" "text" NOT NULL,
    "notice_version" "text" NOT NULL,
    "decision" "text" NOT NULL,
    "acknowledged_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "consent_decision_matches_type" CHECK ((("consent_type" = ANY (ARRAY['relative_leaderboard'::"text", 'training_limits'::"text"])) = ("decision" = ANY (ARRAY['granted'::"text", 'withdrawn'::"text"])))),
    CONSTRAINT "user_consents_decision_check" CHECK (("decision" = ANY (ARRAY['acknowledged'::"text", 'granted'::"text", 'withdrawn'::"text"])))
);


ALTER TABLE "public"."user_consents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_exercise_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "exercise" "text" NOT NULL,
    "frames" "jsonb" NOT NULL,
    "dimensions" integer NOT NULL,
    "frame_count" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_exercise_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_inventory" (
    "user_id" "uuid" NOT NULL,
    "item_key" "text" NOT NULL,
    "quantity" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_inventory_quantity_check" CHECK (("quantity" >= 0))
);


ALTER TABLE "public"."user_inventory" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_inventory"."quantity" IS 'Never negative (CHECK). The per-item max_stack ceiling is enforced by the purchase function, which holds a row lock while it checks.';



CREATE TABLE IF NOT EXISTS "public"."user_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reporter_id" "uuid",
    "reported_user_id" "uuid",
    "reason" "text" NOT NULL,
    "details" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "context_type" "text",
    "context_id" "uuid",
    "context_excerpt" "text",
    CONSTRAINT "user_reports_check" CHECK (("reporter_id" <> "reported_user_id")),
    CONSTRAINT "user_reports_context_check" CHECK (((("context_type" IS NULL) AND ("context_id" IS NULL) AND ("context_excerpt" IS NULL)) OR (("context_type" = ANY (ARRAY['chat'::"text", 'dm'::"text"])) AND ("context_id" IS NOT NULL) AND ("context_excerpt" IS NOT NULL) AND ("char_length"("context_excerpt") <= 500)))),
    CONSTRAINT "user_reports_details_check" CHECK (("char_length"("details") <= 500)),
    CONSTRAINT "user_reports_reason_check" CHECK (("reason" = ANY (ARRAY['harassment'::"text", 'spam'::"text", 'impersonation'::"text", 'inappropriate_content'::"text", 'cheating'::"text", 'other'::"text"]))),
    CONSTRAINT "user_reports_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'reviewed'::"text", 'dismissed'::"text"])))
);


ALTER TABLE "public"."user_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_specialization_xp" (
    "user_id" "uuid" NOT NULL,
    "focus_type" "text" NOT NULL,
    "xp" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "user_specialization_xp_focus_type_check" CHECK (("focus_type" = ANY (ARRAY['hybrid'::"text", 'powerlifter'::"text", 'cali'::"text", 'aesthetic'::"text", 'weightlifter'::"text", 'strongman'::"text", 'tactical'::"text", 'hypertrophy'::"text", 'lifestyle'::"text"]))),
    CONSTRAINT "user_specialization_xp_xp_check" CHECK (("xp" >= 0))
);


ALTER TABLE "public"."user_specialization_xp" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "avatar_url" "text",
    "bio" "text",
    "focus_type" "text" DEFAULT 'hybrid'::"text",
    "rank" "text" DEFAULT 'Beginner'::"text",
    "xp" integer DEFAULT 0,
    "streak" integer DEFAULT 0,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    "weight_kg" numeric(5,2),
    "height_cm" numeric(5,1),
    "sex" "text",
    "age" smallint,
    "goal" "text",
    "strength" integer DEFAULT 0 NOT NULL,
    "agility" integer DEFAULT 0 NOT NULL,
    "vitality" integer DEFAULT 0 NOT NULL,
    "specialization_started_at" timestamp with time zone DEFAULT "now"(),
    "rank_sub_index" integer DEFAULT 1 NOT NULL,
    "deactivated_at" timestamp with time zone,
    "relative_leaderboard_opt_in" boolean DEFAULT false NOT NULL,
    "tour_completed_at" timestamp with time zone,
    CONSTRAINT "users_age_check" CHECK ((("age" > 0) AND ("age" < 120))),
    CONSTRAINT "users_agility_check" CHECK (("agility" >= 0)),
    CONSTRAINT "users_focus_type_check" CHECK (("focus_type" = ANY (ARRAY['hybrid'::"text", 'powerlifter'::"text", 'cali'::"text", 'aesthetic'::"text", 'weightlifter'::"text", 'strongman'::"text", 'tactical'::"text", 'hypertrophy'::"text", 'lifestyle'::"text"]))),
    CONSTRAINT "users_goal_check" CHECK (("goal" = ANY (ARRAY['bulk'::"text", 'cut'::"text", 'maintain'::"text"]))),
    CONSTRAINT "users_height_cm_check" CHECK ((("height_cm" > (0)::numeric) AND ("height_cm" < (300)::numeric))),
    CONSTRAINT "users_rank_sub_index_check" CHECK ((("rank_sub_index" >= 1) AND ("rank_sub_index" <= 10))),
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'moderator'::"text", 'admin'::"text"]))),
    CONSTRAINT "users_sex_check" CHECK (("sex" = ANY (ARRAY['male'::"text", 'female'::"text"]))),
    CONSTRAINT "users_strength_check" CHECK (("strength" >= 0)),
    CONSTRAINT "users_vitality_check" CHECK (("vitality" >= 0)),
    CONSTRAINT "users_weight_kg_check" CHECK ((("weight_kg" > (0)::numeric) AND ("weight_kg" < (500)::numeric)))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON COLUMN "public"."users"."deactivated_at" IS 'Set when the user deactivates their own account; NULL when active. Hides the account from other users. Self-reversible.';



COMMENT ON COLUMN "public"."users"."relative_leaderboard_opt_in" IS 'Explicit opt-in to the bodyweight-relative strength board. Changed only by set_relative_leaderboard(), which also records the decision in user_consents.';



COMMENT ON COLUMN "public"."users"."tour_completed_at" IS 'When the first-run app tour was finished or skipped. NULL = show it once.';



CREATE TABLE IF NOT EXISTS "public"."verification_applications" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "experience_summary" "text" NOT NULL,
    "evidence_count" smallint NOT NULL,
    "evidence_hashes" "text"[] NOT NULL,
    "evidence_sizes" integer[] NOT NULL,
    "notice_version" "text" NOT NULL,
    "submitted_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "decided_at" timestamp with time zone,
    "decided_by" "uuid",
    "decision_reason" "text",
    "withdrawn_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "revoked_by" "uuid",
    "revoked_by_self" boolean,
    "revoke_reason" "text",
    "files_deleted_at" timestamp with time zone,
    CONSTRAINT "decision_fields_match_status" CHECK (((("status" = ANY (ARRAY['approved'::"text", 'rejected'::"text", 'revoked'::"text"])) = (("decided_at" IS NOT NULL) AND ("decided_by" IS NOT NULL))) AND (("status" <> 'rejected'::"text") OR ("decision_reason" IS NOT NULL)) AND (("status" = 'withdrawn'::"text") = ("withdrawn_at" IS NOT NULL)) AND (("status" = 'revoked'::"text") = (("revoked_at" IS NOT NULL) AND ("revoked_by" IS NOT NULL) AND ("revoked_by_self" IS NOT NULL))) AND (("status" <> 'pending'::"text") OR ("files_deleted_at" IS NULL)))),
    CONSTRAINT "evidence_arrays_match" CHECK ((("cardinality"("evidence_hashes") = "evidence_count") AND ("cardinality"("evidence_sizes") = "evidence_count"))),
    CONSTRAINT "evidence_hashes_are_sha256" CHECK (("array_to_string"("evidence_hashes", ','::"text") ~ '^[0-9a-f]{64}(,[0-9a-f]{64})*$'::"text")),
    CONSTRAINT "verification_applications_decision_reason_check" CHECK ((("decision_reason" IS NULL) OR (("char_length"("decision_reason") >= 1) AND ("char_length"("decision_reason") <= 500)))),
    CONSTRAINT "verification_applications_evidence_count_check" CHECK ((("evidence_count" >= 1) AND ("evidence_count" <= 3))),
    CONSTRAINT "verification_applications_experience_summary_check" CHECK ((("char_length"("experience_summary") >= 50) AND ("char_length"("experience_summary") <= 2000))),
    CONSTRAINT "verification_applications_kind_check" CHECK (("kind" = 'coach'::"text")),
    CONSTRAINT "verification_applications_revoke_reason_check" CHECK ((("revoke_reason" IS NULL) OR (("char_length"("revoke_reason") >= 1) AND ("char_length"("revoke_reason") <= 500)))),
    CONSTRAINT "verification_applications_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'withdrawn'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."verification_applications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workout_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "exercise" "text" NOT NULL,
    "sets" integer,
    "reps" integer,
    "rep_quality_score" double precision DEFAULT 1.0,
    "xp_earned" integer DEFAULT 0,
    "logged_at" timestamp without time zone DEFAULT "now"(),
    "base_xp" integer,
    "quality_multiplier" numeric(4,2) DEFAULT 1.0,
    "workout_source" "text" DEFAULT 'manual'::"text",
    "weight_kg" numeric(6,2),
    "duration_seconds" integer,
    "distance_m" numeric(10,2),
    CONSTRAINT "workout_logs_distance_m_check" CHECK ((("distance_m" IS NULL) OR (("distance_m" >= (0)::numeric) AND ("distance_m" <= (200000)::numeric)))),
    CONSTRAINT "workout_logs_duration_seconds_check" CHECK ((("duration_seconds" IS NULL) OR (("duration_seconds" >= 0) AND ("duration_seconds" <= 21600)))),
    CONSTRAINT "workout_logs_weight_kg_check" CHECK ((("weight_kg" >= (0)::numeric) AND ("weight_kg" <= (500)::numeric)))
);


ALTER TABLE "public"."workout_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."xp_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "workout_source" "text" NOT NULL,
    "exercise_name" "text" DEFAULT '*'::"text" NOT NULL,
    "reps_multiplier" numeric(4,2) NOT NULL,
    "quality_bonus_max" numeric(4,2) DEFAULT 0.0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "duration_multiplier" numeric(6,2),
    "distance_multiplier" numeric(6,2)
);


ALTER TABLE "public"."xp_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."xp_grants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "amount" integer NOT NULL,
    "source_type" "text" NOT NULL,
    "source_id" "uuid",
    "focus_type" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "xp_grants_amount_check" CHECK (("amount" > 0)),
    CONSTRAINT "xp_grants_source_type_check" CHECK (("source_type" = ANY (ARRAY['mission_first_clear'::"text", 'dungeon_clear'::"text", 'dungeon_consolation'::"text", 'admin_adjustment'::"text"])))
);


ALTER TABLE "public"."xp_grants" OWNER TO "postgres";


COMMENT ON TABLE "public"."xp_grants" IS 'XP awarded outside a workout (mission/dungeon clears, admin adjustments). UNIQUE(user_id, source_type, source_id) is the exactly-once guarantee for a reward payout.';



ALTER TABLE ONLY "public"."admin_audit_log"
    ADD CONSTRAINT "admin_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_suggestions"
    ADD CONSTRAINT "ai_suggestions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bosses"
    ADD CONSTRAINT "bosses_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."bosses"
    ADD CONSTRAINT "bosses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bug_reports"
    ADD CONSTRAINT "bug_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."collectibles"
    ADD CONSTRAINT "collectibles_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."collectibles"
    ADD CONSTRAINT "collectibles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commodity_reference_prices"
    ADD CONSTRAINT "commodity_reference_prices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."direct_messages"
    ADD CONSTRAINT "direct_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dungeon_assignments"
    ADD CONSTRAINT "dungeon_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dungeon_battles"
    ADD CONSTRAINT "dungeon_battles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dungeon_clears"
    ADD CONSTRAINT "dungeon_clears_pkey" PRIMARY KEY ("event_id", "user_id");



ALTER TABLE ONLY "public"."dungeon_event_invites"
    ADD CONSTRAINT "dungeon_event_invites_pkey" PRIMARY KEY ("event_id", "user_id");



ALTER TABLE ONLY "public"."dungeon_events"
    ADD CONSTRAINT "dungeon_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dungeon_objective_results"
    ADD CONSTRAINT "dungeon_objective_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dungeon_reward_pool"
    ADD CONSTRAINT "dungeon_reward_pool_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dungeon_runs"
    ADD CONSTRAINT "dungeon_runs_battle_id_user_id_key" UNIQUE ("battle_id", "user_id");



ALTER TABLE ONLY "public"."dungeon_runs"
    ADD CONSTRAINT "dungeon_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."exercise_library"
    ADD CONSTRAINT "exercise_library_pkey" PRIMARY KEY ("exercise");



ALTER TABLE ONLY "public"."exercises"
    ADD CONSTRAINT "exercises_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."exercises"
    ADD CONSTRAINT "exercises_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fitrack_logs"
    ADD CONSTRAINT "fitrack_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."food_servings"
    ADD CONSTRAINT "food_servings_food_id_label_key" UNIQUE ("food_id", "label");



ALTER TABLE ONLY "public"."food_servings"
    ADD CONSTRAINT "food_servings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."foods"
    ADD CONSTRAINT "foods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."foods"
    ADD CONSTRAINT "foods_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."game_config"
    ADD CONSTRAINT "game_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."gold_ledger"
    ADD CONSTRAINT "gold_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gymmunity_posts"
    ADD CONSTRAINT "gymmunity_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."item_uses"
    ADD CONSTRAINT "item_uses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."market_commodities"
    ADD CONSTRAINT "market_commodities_id_purchase_unit_key" UNIQUE ("id", "purchase_unit");



ALTER TABLE ONLY "public"."market_commodities"
    ADD CONSTRAINT "market_commodities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."market_commodities"
    ADD CONSTRAINT "market_commodities_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."mission_attempts"
    ADD CONSTRAINT "mission_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mission_chapters"
    ADD CONSTRAINT "mission_chapters_number_key" UNIQUE ("number");



ALTER TABLE ONLY "public"."mission_chapters"
    ADD CONSTRAINT "mission_chapters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mission_clears"
    ADD CONSTRAINT "mission_clears_pkey" PRIMARY KEY ("user_id", "mission_id");



ALTER TABLE ONLY "public"."mission_objective_results"
    ADD CONSTRAINT "mission_objective_results_attempt_id_objective_id_key" UNIQUE ("attempt_id", "objective_id");



ALTER TABLE ONLY "public"."mission_objective_results"
    ADD CONSTRAINT "mission_objective_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mission_objectives"
    ADD CONSTRAINT "mission_objectives_mission_id_sequence_key" UNIQUE ("mission_id", "sequence");



ALTER TABLE ONLY "public"."mission_objectives"
    ADD CONSTRAINT "mission_objectives_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_chapter_id_level_number_key" UNIQUE ("chapter_id", "level_number");



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."privacy_export_coverage"
    ADD CONSTRAINT "privacy_export_coverage_pkey" PRIMARY KEY ("table_name", "column_name");



ALTER TABLE ONLY "public"."privacy_notices"
    ADD CONSTRAINT "privacy_notices_pkey" PRIMARY KEY ("consent_type", "version");



ALTER TABLE ONLY "public"."rank_history"
    ADD CONSTRAINT "rank_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rank_thresholds"
    ADD CONSTRAINT "rank_thresholds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rarities"
    ADD CONSTRAINT "rarities_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."rate_limits"
    ADD CONSTRAINT "rate_limits_pkey" PRIMARY KEY ("user_id", "action");



ALTER TABLE ONLY "public"."routine_exercises"
    ADD CONSTRAINT "routine_exercises_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."routine_exercises"
    ADD CONSTRAINT "routine_exercises_routine_id_position_key" UNIQUE ("routine_id", "position");



ALTER TABLE ONLY "public"."routines"
    ADD CONSTRAINT "routines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_items"
    ADD CONSTRAINT "shop_items_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."shop_purchases"
    ADD CONSTRAINT "shop_purchases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_purchases"
    ADD CONSTRAINT "shop_purchases_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."specialization_affinity"
    ADD CONSTRAINT "specialization_affinity_focus_type_match_type_match_value_key" UNIQUE ("focus_type", "match_type", "match_value");



ALTER TABLE ONLY "public"."specialization_affinity"
    ADD CONSTRAINT "specialization_affinity_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."streak_shields"
    ADD CONSTRAINT "streak_shields_pkey" PRIMARY KEY ("user_id", "covered_date");



ALTER TABLE ONLY "public"."strength_records"
    ADD CONSTRAINT "strength_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."threat_ranks"
    ADD CONSTRAINT "threat_ranks_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."training_limits"
    ADD CONSTRAINT "training_limits_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."training_plan_days"
    ADD CONSTRAINT "training_plan_days_pkey" PRIMARY KEY ("plan_id", "day");



ALTER TABLE ONLY "public"."training_plan_feedback"
    ADD CONSTRAINT "training_plan_feedback_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."training_plans"
    ADD CONSTRAINT "training_plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."training_surveys"
    ADD CONSTRAINT "training_surveys_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_budget_settings"
    ADD CONSTRAINT "user_budget_settings_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_collectibles"
    ADD CONSTRAINT "user_collectibles_pkey" PRIMARY KEY ("user_id", "collectible_id");



ALTER TABLE ONLY "public"."user_commodity_prices"
    ADD CONSTRAINT "user_commodity_prices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_consents"
    ADD CONSTRAINT "user_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_exercise_templates"
    ADD CONSTRAINT "user_exercise_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_exercise_templates"
    ADD CONSTRAINT "user_exercise_templates_user_id_exercise_key" UNIQUE ("user_id", "exercise");



ALTER TABLE ONLY "public"."user_inventory"
    ADD CONSTRAINT "user_inventory_pkey" PRIMARY KEY ("user_id", "item_key");



ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_specialization_xp"
    ADD CONSTRAINT "user_specialization_xp_pkey" PRIMARY KEY ("user_id", "focus_type");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."verification_applications"
    ADD CONSTRAINT "verification_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workout_logs"
    ADD CONSTRAINT "workout_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."xp_config"
    ADD CONSTRAINT "xp_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."xp_config"
    ADD CONSTRAINT "xp_config_workout_source_exercise_name_key" UNIQUE ("workout_source", "exercise_name");



ALTER TABLE ONLY "public"."xp_grants"
    ADD CONSTRAINT "xp_grants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."xp_grants"
    ADD CONSTRAINT "xp_grants_unique_source" UNIQUE ("user_id", "source_type", "source_id");



CREATE INDEX "admin_audit_log_created_idx" ON "public"."admin_audit_log" USING "btree" ("created_at" DESC);



CREATE INDEX "admin_audit_log_target_idx" ON "public"."admin_audit_log" USING "btree" ("target_type", "target_id");



CREATE INDEX "bug_reports_status_idx" ON "public"."bug_reports" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "chat_messages_created_at_idx" ON "public"."chat_messages" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "commodity_reference_prices_da_week_key" ON "public"."commodity_reference_prices" USING "btree" ("commodity_id", "source", "region", "period_start") WHERE ("source" = 'da_bantay_presyo'::"text");



CREATE INDEX "commodity_reference_prices_latest_idx" ON "public"."commodity_reference_prices" USING "btree" ("commodity_id", "period_end" DESC);



CREATE INDEX "direct_messages_pair_created_idx" ON "public"."direct_messages" USING "btree" ("sender_id", "recipient_id", "created_at" DESC);



CREATE INDEX "direct_messages_pair_idx" ON "public"."direct_messages" USING "btree" (LEAST("sender_id", "recipient_id"), GREATEST("sender_id", "recipient_id"), "created_at");



CREATE UNIQUE INDEX "dungeon_assignments_one_active_per_run" ON "public"."dungeon_assignments" USING "btree" ("run_id") WHERE ("status" = 'active'::"text");



CREATE UNIQUE INDEX "dungeon_assignments_unique_active_exercise" ON "public"."dungeon_assignments" USING "btree" ("battle_id", "exercise") WHERE ("status" = 'active'::"text");



CREATE INDEX "dungeon_battles_event_status_idx" ON "public"."dungeon_battles" USING "btree" ("event_id", "status");



CREATE INDEX "dungeon_objective_results_actor_idx" ON "public"."dungeon_objective_results" USING "btree" ("actor_run_id");



CREATE UNIQUE INDEX "dungeon_runs_one_live_per_event" ON "public"."dungeon_runs" USING "btree" ("event_id", "user_id") WHERE ("status" = ANY (ARRAY['joined'::"text", 'ready'::"text", 'active'::"text", 'disconnected'::"text", 'downed'::"text"]));



CREATE INDEX "fitrack_logs_user_id_logged_at_idx" ON "public"."fitrack_logs" USING "btree" ("user_id", "logged_at");



CREATE INDEX "food_servings_food_id_idx" ON "public"."food_servings" USING "btree" ("food_id", "sort_order");



CREATE INDEX "foods_search_text_trgm" ON "public"."foods" USING "gin" ("search_text" "extensions"."gin_trgm_ops");



CREATE INDEX "friendships_addressee_idx" ON "public"."friendships" USING "btree" ("addressee_id", "status");



CREATE INDEX "friendships_requester_idx" ON "public"."friendships" USING "btree" ("requester_id", "status");



CREATE UNIQUE INDEX "friendships_unique_pair_idx" ON "public"."friendships" USING "btree" (LEAST("requester_id", "addressee_id"), GREATEST("requester_id", "addressee_id"));



CREATE UNIQUE INDEX "gold_ledger_idempotency_key_idx" ON "public"."gold_ledger" USING "btree" ("idempotency_key") WHERE ("idempotency_key" IS NOT NULL);



CREATE INDEX "gold_ledger_user_created_idx" ON "public"."gold_ledger" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "gold_ledger_user_id_idx" ON "public"."gold_ledger" USING "btree" ("user_id");



CREATE INDEX "gymmunity_posts_status_created_at_idx" ON "public"."gymmunity_posts" USING "btree" ("status", "created_at");



CREATE INDEX "gymmunity_posts_user_id_idx" ON "public"."gymmunity_posts" USING "btree" ("user_id");



CREATE UNIQUE INDEX "idx_rank_thresholds_focus_tier" ON "public"."rank_thresholds" USING "btree" ("focus_type", "tier_index");



CREATE INDEX "idx_strength_records_absolute" ON "public"."strength_records" USING "btree" ("exercise", "e1rm_kg" DESC);



CREATE INDEX "idx_strength_records_relative" ON "public"."strength_records" USING "btree" ("exercise", "relative_e1rm" DESC) WHERE ("relative_e1rm" IS NOT NULL);



CREATE INDEX "idx_strength_records_user_exercise" ON "public"."strength_records" USING "btree" ("user_id", "exercise", "e1rm_kg" DESC);



CREATE INDEX "idx_user_specialization_xp_focus" ON "public"."user_specialization_xp" USING "btree" ("focus_type", "xp" DESC);



CREATE INDEX "item_uses_user_item_idx" ON "public"."item_uses" USING "btree" ("user_id", "item_key", "used_at" DESC);



CREATE UNIQUE INDEX "mission_attempts_one_active_per_user" ON "public"."mission_attempts" USING "btree" ("user_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "mission_attempts_user_mission_idx" ON "public"."mission_attempts" USING "btree" ("user_id", "mission_id", "started_at" DESC);



CREATE INDEX "routine_exercises_routine_idx" ON "public"."routine_exercises" USING "btree" ("routine_id");



CREATE INDEX "routines_user_idx" ON "public"."routines" USING "btree" ("user_id");



CREATE INDEX "shop_purchases_user_item_idx" ON "public"."shop_purchases" USING "btree" ("user_id", "item_key", "created_at" DESC);



CREATE UNIQUE INDEX "training_plan_feedback_one_per_day" ON "public"."training_plan_feedback" USING "btree" ("plan_id", "day") WHERE ("day" IS NOT NULL);



CREATE UNIQUE INDEX "training_plans_one_active" ON "public"."training_plans" USING "btree" ("user_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "training_plans_user_idx" ON "public"."training_plans" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "user_commodity_prices_latest_idx" ON "public"."user_commodity_prices" USING "btree" ("user_id", "commodity_id", "entered_at" DESC);



CREATE INDEX "user_consents_latest_idx" ON "public"."user_consents" USING "btree" ("user_id", "consent_type", "acknowledged_at" DESC);



CREATE INDEX "user_exercise_templates_user_idx" ON "public"."user_exercise_templates" USING "btree" ("user_id");



CREATE INDEX "user_reports_reported_user_idx" ON "public"."user_reports" USING "btree" ("reported_user_id");



CREATE INDEX "user_reports_status_idx" ON "public"."user_reports" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "verification_by_status" ON "public"."verification_applications" USING "btree" ("status", "submitted_at" DESC);



CREATE UNIQUE INDEX "verification_one_approved" ON "public"."verification_applications" USING "btree" ("user_id", "kind") WHERE ("status" = 'approved'::"text");



CREATE UNIQUE INDEX "verification_one_pending" ON "public"."verification_applications" USING "btree" ("user_id", "kind") WHERE ("status" = 'pending'::"text");



CREATE INDEX "xp_grants_user_idx" ON "public"."xp_grants" USING "btree" ("user_id", "created_at" DESC);



CREATE OR REPLACE TRIGGER "admin_audit_log_immutable" BEFORE DELETE OR UPDATE ON "public"."admin_audit_log" FOR EACH ROW EXECUTE FUNCTION "public"."refuse_record_change"();



CREATE OR REPLACE TRIGGER "commodity_reference_prices_immutable" BEFORE UPDATE ON "public"."commodity_reference_prices" FOR EACH ROW EXECUTE FUNCTION "public"."refuse_price_history_update"();



CREATE OR REPLACE TRIGGER "dungeon_assignments_camera_eligible" BEFORE INSERT ON "public"."dungeon_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."assert_camera_objective_eligible"();



CREATE OR REPLACE TRIGGER "foods_search_text" BEFORE INSERT OR UPDATE ON "public"."foods" FOR EACH ROW EXECUTE FUNCTION "public"."foods_set_search_text"();



CREATE OR REPLACE TRIGGER "mission_objectives_camera_eligible" BEFORE INSERT OR UPDATE OF "exercise" ON "public"."mission_objectives" FOR EACH ROW EXECUTE FUNCTION "public"."assert_camera_objective_eligible"();



CREATE OR REPLACE TRIGGER "missions_validate_publish" AFTER INSERT OR UPDATE OF "is_active", "max_hp" ON "public"."missions" FOR EACH ROW EXECUTE FUNCTION "public"."missions_validate_publish"();



CREATE OR REPLACE TRIGGER "privacy_notices_immutable" BEFORE DELETE OR UPDATE ON "public"."privacy_notices" FOR EACH ROW EXECUTE FUNCTION "public"."refuse_record_change"();



CREATE OR REPLACE TRIGGER "streak_shields_refresh_streak" AFTER INSERT OR DELETE ON "public"."streak_shields" FOR EACH ROW EXECUTE FUNCTION "public"."refresh_user_streak"();



CREATE OR REPLACE TRIGGER "trg_derive_strength_record" AFTER INSERT ON "public"."workout_logs" FOR EACH ROW EXECUTE FUNCTION "public"."derive_strength_record"();



CREATE OR REPLACE TRIGGER "user_commodity_prices_immutable" BEFORE UPDATE ON "public"."user_commodity_prices" FOR EACH ROW EXECUTE FUNCTION "public"."refuse_price_history_update"();



CREATE OR REPLACE TRIGGER "user_consents_immutable" BEFORE DELETE OR UPDATE ON "public"."user_consents" FOR EACH ROW EXECUTE FUNCTION "public"."guard_user_consents"();



CREATE OR REPLACE TRIGGER "verification_applications_guard" BEFORE DELETE OR UPDATE ON "public"."verification_applications" FOR EACH ROW EXECUTE FUNCTION "public"."guard_verification_applications"();



CREATE OR REPLACE TRIGGER "workout_logs_refresh_streak" AFTER INSERT ON "public"."workout_logs" FOR EACH ROW EXECUTE FUNCTION "public"."refresh_user_streak"();



ALTER TABLE ONLY "public"."ai_suggestions"
    ADD CONSTRAINT "ai_suggestions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bug_reports"
    ADD CONSTRAINT "bug_reports_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bug_reports"
    ADD CONSTRAINT "bug_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."collectibles"
    ADD CONSTRAINT "collectibles_rarity_fkey" FOREIGN KEY ("rarity") REFERENCES "public"."rarities"("key");



ALTER TABLE ONLY "public"."commodity_reference_prices"
    ADD CONSTRAINT "commodity_reference_prices_commodity_id_unit_fkey" FOREIGN KEY ("commodity_id", "unit") REFERENCES "public"."market_commodities"("id", "purchase_unit") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."direct_messages"
    ADD CONSTRAINT "direct_messages_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."direct_messages"
    ADD CONSTRAINT "direct_messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_assignments"
    ADD CONSTRAINT "dungeon_assignments_battle_id_fkey" FOREIGN KEY ("battle_id") REFERENCES "public"."dungeon_battles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_assignments"
    ADD CONSTRAINT "dungeon_assignments_exercise_fkey" FOREIGN KEY ("exercise") REFERENCES "public"."exercises"("name");



ALTER TABLE ONLY "public"."dungeon_assignments"
    ADD CONSTRAINT "dungeon_assignments_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "public"."dungeon_runs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_battles"
    ADD CONSTRAINT "dungeon_battles_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."dungeon_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_battles"
    ADD CONSTRAINT "dungeon_battles_leader_id_fkey" FOREIGN KEY ("leader_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dungeon_clears"
    ADD CONSTRAINT "dungeon_clears_battle_id_fkey" FOREIGN KEY ("battle_id") REFERENCES "public"."dungeon_battles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dungeon_clears"
    ADD CONSTRAINT "dungeon_clears_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."dungeon_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_clears"
    ADD CONSTRAINT "dungeon_clears_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_event_invites"
    ADD CONSTRAINT "dungeon_event_invites_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."dungeon_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_event_invites"
    ADD CONSTRAINT "dungeon_event_invites_invited_by_fkey" FOREIGN KEY ("invited_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dungeon_event_invites"
    ADD CONSTRAINT "dungeon_event_invites_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_events"
    ADD CONSTRAINT "dungeon_events_boss_id_fkey" FOREIGN KEY ("boss_id") REFERENCES "public"."bosses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dungeon_events"
    ADD CONSTRAINT "dungeon_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dungeon_events"
    ADD CONSTRAINT "dungeon_events_threat_rank_fkey" FOREIGN KEY ("threat_rank") REFERENCES "public"."threat_ranks"("key");



ALTER TABLE ONLY "public"."dungeon_objective_results"
    ADD CONSTRAINT "dungeon_objective_results_actor_run_id_fkey" FOREIGN KEY ("actor_run_id") REFERENCES "public"."dungeon_runs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_objective_results"
    ADD CONSTRAINT "dungeon_objective_results_assignment_id_fkey" FOREIGN KEY ("assignment_id") REFERENCES "public"."dungeon_assignments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_objective_results"
    ADD CONSTRAINT "dungeon_objective_results_workout_log_id_fkey" FOREIGN KEY ("workout_log_id") REFERENCES "public"."workout_logs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dungeon_reward_pool"
    ADD CONSTRAINT "dungeon_reward_pool_collectible_id_fkey" FOREIGN KEY ("collectible_id") REFERENCES "public"."collectibles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_reward_pool"
    ADD CONSTRAINT "dungeon_reward_pool_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."dungeon_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_runs"
    ADD CONSTRAINT "dungeon_runs_battle_id_fkey" FOREIGN KEY ("battle_id") REFERENCES "public"."dungeon_battles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_runs"
    ADD CONSTRAINT "dungeon_runs_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."dungeon_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dungeon_runs"
    ADD CONSTRAINT "dungeon_runs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."exercise_library"
    ADD CONSTRAINT "exercise_library_exercise_fkey" FOREIGN KEY ("exercise") REFERENCES "public"."exercises"("name") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fitrack_logs"
    ADD CONSTRAINT "fitrack_logs_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "public"."foods"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."fitrack_logs"
    ADD CONSTRAINT "fitrack_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."food_servings"
    ADD CONSTRAINT "food_servings_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "public"."foods"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_addressee_id_fkey" FOREIGN KEY ("addressee_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gold_ledger"
    ADD CONSTRAINT "gold_ledger_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gymmunity_posts"
    ADD CONSTRAINT "gymmunity_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."item_uses"
    ADD CONSTRAINT "item_uses_item_key_fkey" FOREIGN KEY ("item_key") REFERENCES "public"."shop_items"("key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."item_uses"
    ADD CONSTRAINT "item_uses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."market_commodities"
    ADD CONSTRAINT "market_commodities_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "public"."foods"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."mission_attempts"
    ADD CONSTRAINT "mission_attempts_mission_id_fkey" FOREIGN KEY ("mission_id") REFERENCES "public"."missions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mission_attempts"
    ADD CONSTRAINT "mission_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mission_clears"
    ADD CONSTRAINT "mission_clears_attempt_id_fkey" FOREIGN KEY ("attempt_id") REFERENCES "public"."mission_attempts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mission_clears"
    ADD CONSTRAINT "mission_clears_mission_id_fkey" FOREIGN KEY ("mission_id") REFERENCES "public"."missions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mission_clears"
    ADD CONSTRAINT "mission_clears_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mission_objective_results"
    ADD CONSTRAINT "mission_objective_results_attempt_id_fkey" FOREIGN KEY ("attempt_id") REFERENCES "public"."mission_attempts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mission_objective_results"
    ADD CONSTRAINT "mission_objective_results_objective_id_fkey" FOREIGN KEY ("objective_id") REFERENCES "public"."mission_objectives"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mission_objective_results"
    ADD CONSTRAINT "mission_objective_results_workout_log_id_fkey" FOREIGN KEY ("workout_log_id") REFERENCES "public"."workout_logs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mission_objectives"
    ADD CONSTRAINT "mission_objectives_exercise_fkey" FOREIGN KEY ("exercise") REFERENCES "public"."exercises"("name");



ALTER TABLE ONLY "public"."mission_objectives"
    ADD CONSTRAINT "mission_objectives_mission_id_fkey" FOREIGN KEY ("mission_id") REFERENCES "public"."missions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_boss_id_fkey" FOREIGN KEY ("boss_id") REFERENCES "public"."bosses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "public"."mission_chapters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_reward_collectible_id_fkey" FOREIGN KEY ("reward_collectible_id") REFERENCES "public"."collectibles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."rank_history"
    ADD CONSTRAINT "rank_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."routine_exercises"
    ADD CONSTRAINT "routine_exercises_exercise_fkey" FOREIGN KEY ("exercise") REFERENCES "public"."exercises"("name");



ALTER TABLE ONLY "public"."routine_exercises"
    ADD CONSTRAINT "routine_exercises_routine_id_fkey" FOREIGN KEY ("routine_id") REFERENCES "public"."routines"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."routines"
    ADD CONSTRAINT "routines_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_purchases"
    ADD CONSTRAINT "shop_purchases_item_key_fkey" FOREIGN KEY ("item_key") REFERENCES "public"."shop_items"("key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_purchases"
    ADD CONSTRAINT "shop_purchases_ledger_id_fkey" FOREIGN KEY ("ledger_id") REFERENCES "public"."gold_ledger"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."shop_purchases"
    ADD CONSTRAINT "shop_purchases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."streak_shields"
    ADD CONSTRAINT "streak_shields_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."strength_records"
    ADD CONSTRAINT "strength_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."strength_records"
    ADD CONSTRAINT "strength_records_workout_log_id_fkey" FOREIGN KEY ("workout_log_id") REFERENCES "public"."workout_logs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."training_limits"
    ADD CONSTRAINT "training_limits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."training_plan_days"
    ADD CONSTRAINT "training_plan_days_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."training_plans"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."training_plan_feedback"
    ADD CONSTRAINT "training_plan_feedback_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."training_plans"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."training_plan_feedback"
    ADD CONSTRAINT "training_plan_feedback_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."training_plans"
    ADD CONSTRAINT "training_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."training_surveys"
    ADD CONSTRAINT "training_surveys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_budget_settings"
    ADD CONSTRAINT "user_budget_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_collectibles"
    ADD CONSTRAINT "user_collectibles_collectible_id_fkey" FOREIGN KEY ("collectible_id") REFERENCES "public"."collectibles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_collectibles"
    ADD CONSTRAINT "user_collectibles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_commodity_prices"
    ADD CONSTRAINT "user_commodity_prices_commodity_id_unit_fkey" FOREIGN KEY ("commodity_id", "unit") REFERENCES "public"."market_commodities"("id", "purchase_unit") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_commodity_prices"
    ADD CONSTRAINT "user_commodity_prices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_consents"
    ADD CONSTRAINT "user_consents_consent_type_notice_version_fkey" FOREIGN KEY ("consent_type", "notice_version") REFERENCES "public"."privacy_notices"("consent_type", "version");



ALTER TABLE ONLY "public"."user_consents"
    ADD CONSTRAINT "user_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_exercise_templates"
    ADD CONSTRAINT "user_exercise_templates_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_inventory"
    ADD CONSTRAINT "user_inventory_item_key_fkey" FOREIGN KEY ("item_key") REFERENCES "public"."shop_items"("key") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_inventory"
    ADD CONSTRAINT "user_inventory_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_reported_user_id_fkey" FOREIGN KEY ("reported_user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_specialization_xp"
    ADD CONSTRAINT "user_specialization_xp_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_applications"
    ADD CONSTRAINT "verification_applications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."workout_logs"
    ADD CONSTRAINT "workout_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."xp_grants"
    ADD CONSTRAINT "xp_grants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."admin_audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "affinity readable by all" ON "public"."specialization_affinity" FOR SELECT USING (true);



ALTER TABLE "public"."ai_suggestions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bosses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bug_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."collectibles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commodity_reference_prices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."direct_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_battles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_clears" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_event_invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_objective_results" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_reward_pool" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dungeon_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."exercise_library" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."exercises" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fitrack_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."food_servings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."foods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."friendships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."game_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gold_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gymmunity_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."item_uses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."market_commodities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mission_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mission_chapters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mission_clears" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mission_objective_results" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mission_objectives" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."missions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "own routine exercises: all" ON "public"."routine_exercises" USING ((EXISTS ( SELECT 1
   FROM "public"."routines" "r"
  WHERE (("r"."id" = "routine_exercises"."routine_id") AND ("r"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."routines" "r"
  WHERE (("r"."id" = "routine_exercises"."routine_id") AND ("r"."user_id" = "auth"."uid"())))));



CREATE POLICY "own routines: all" ON "public"."routines" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "own specialization xp readable" ON "public"."user_specialization_xp" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "own strength records readable" ON "public"."strength_records" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "own templates: delete" ON "public"."user_exercise_templates" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "own templates: insert" ON "public"."user_exercise_templates" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "own templates: select" ON "public"."user_exercise_templates" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "own templates: update" ON "public"."user_exercise_templates" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."privacy_export_coverage" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."privacy_notices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rank_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rank_thresholds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rarities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."routine_exercises" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."routines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shop_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shop_purchases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."specialization_affinity" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."streak_shields" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."strength_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."threat_ranks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."training_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."training_plan_days" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."training_plan_feedback" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."training_plans" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."training_surveys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_budget_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_collectibles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_commodity_prices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_consents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_exercise_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_inventory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_specialization_xp" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."verification_applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workout_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."xp_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."xp_grants" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."abandon_mission_attempt"("p_user_id" "uuid", "p_attempt_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."abandon_mission_attempt"("p_user_id" "uuid", "p_attempt_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_cancel_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_cancel_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_create_dungeon_event"("p_admin_id" "uuid", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_dungeon_event"("p_admin_id" "uuid", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_food_json"("p_food_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_food_json"("p_food_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_dungeon_events"("p_admin_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_dungeon_events"("p_admin_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_foods"("p_query" "text", "p_include_hidden" boolean, "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_foods"("p_query" "text", "p_include_hidden" boolean, "p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_verification_applications"("p_scope" "text", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_verification_applications"("p_scope" "text", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_open_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid", "p_duration_hours" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_open_dungeon_event"("p_admin_id" "uuid", "p_event_id" "uuid", "p_duration_hours" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_save_food"("p_food_id" "uuid", "p_expected_updated_at" timestamp with time zone, "p_food" "jsonb", "p_servings" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_save_food"("p_food_id" "uuid", "p_expected_updated_at" timestamp with time zone, "p_food" "jsonb", "p_servings" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_dungeon_reward_pool"("p_admin_id" "uuid", "p_event_id" "uuid", "p_entries" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_dungeon_reward_pool"("p_admin_id" "uuid", "p_event_id" "uuid", "p_entries" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_food_active"("p_food_id" "uuid", "p_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_food_active"("p_food_id" "uuid", "p_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_reference_price"("p_commodity_slug" "text", "p_price_php" numeric, "p_note" "text", "p_day" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_reference_price"("p_commodity_slug" "text", "p_price_php" numeric, "p_note" "text", "p_day" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_xp_gain"("p_user_id" "uuid", "p_xp" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_xp_gain"("p_user_id" "uuid", "p_xp" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_camera_objective_eligible"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_camera_objective_eligible"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_can_manage_dungeons"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_can_manage_dungeons"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_mission_is_clearable"("p_mission_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_mission_is_clearable"("p_mission_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_result_plausible"("p_exercise" "text", "p_metric_type" "text", "p_achieved" numeric, "p_elapsed_s" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_result_plausible"("p_exercise" "text", "p_metric_type" "text", "p_achieved" numeric, "p_elapsed_s" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_dungeon_objective"("p_battle_id" "uuid", "p_run_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_dungeon_objective"("p_battle_id" "uuid", "p_run_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."award_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid", "p_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."award_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid", "p_idempotency_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."begin_coach_application"("p_application_id" "uuid", "p_user_id" "uuid", "p_summary" "text", "p_hashes" "text"[], "p_sizes" integer[], "p_notice_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."begin_coach_application"("p_application_id" "uuid", "p_user_id" "uuid", "p_summary" "text", "p_hashes" "text"[], "p_sizes" integer[], "p_notice_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."camera_lifecycle_validated"("p_exercise" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."camera_lifecycle_validated"("p_exercise" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."camera_reward_eligible"("p_exercise" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."camera_reward_eligible"("p_exercise" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."camera_reward_eligible_exercises"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."camera_reward_eligible_exercises"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_rate_limit"("p_user_id" "uuid", "p_action" "text", "p_max" integer, "p_window_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_rate_limit"("p_user_id" "uuid", "p_action" "text", "p_max" integer, "p_window_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."coach_application_block"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_application_block"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."compute_streak"("p_user_id" "uuid", "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."compute_streak"("p_user_id" "uuid", "p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_dungeon_battle"("p_user_id" "uuid", "p_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_dungeon_battle"("p_user_id" "uuid", "p_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_notice_version"("p_consent_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_notice_version"("p_consent_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."decide_verification_application"("p_application_id" "uuid", "p_admin_id" "uuid", "p_decision" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decide_verification_application"("p_application_id" "uuid", "p_admin_id" "uuid", "p_decision" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."derive_strength_record"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."derive_strength_record"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."equip_collectible"("p_user_id" "uuid", "p_collectible_id" "uuid", "p_equipped" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."equip_collectible"("p_user_id" "uuid", "p_collectible_id" "uuid", "p_equipped" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."export_coverage_gaps"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."export_coverage_gaps"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."export_user_data"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."export_user_data"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."foods_set_search_text"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."foods_set_search_text"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."game_timezone"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."game_timezone"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_budget_data"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_budget_data"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_collection"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_collection"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_current_notices"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_current_notices"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_dungeon_battle_state"("p_user_id" "uuid", "p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_dungeon_battle_state"("p_user_id" "uuid", "p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_dungeon_events"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_dungeon_events"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_dungeon_leaderboard"("p_user_id" "uuid", "p_scope" "text", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_dungeon_leaderboard"("p_user_id" "uuid", "p_scope" "text", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_joinable_dungeon_battles"("p_user_id" "uuid", "p_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_joinable_dungeon_battles"("p_user_id" "uuid", "p_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_mission_board"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_mission_board"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_verification"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_verification"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_privacy_status"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_privacy_status"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_public_verification"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_public_verification"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_shop"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_shop"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."gold_balance"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."gold_balance"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."grant_bonus_xp"("p_user_id" "uuid", "p_amount" integer, "p_source_type" "text", "p_source_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."grant_bonus_xp"("p_user_id" "uuid", "p_amount" integer, "p_source_type" "text", "p_source_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_user_consents"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_user_consents"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_verification_applications"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_verification_applications"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."has_current_consent"("p_user_id" "uuid", "p_consent_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."has_current_consent"("p_user_id" "uuid", "p_consent_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."join_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_admin_audit_log"("p_limit" integer, "p_before" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_admin_audit_log"("p_limit" integer, "p_before" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."log_meal_entry"("p_user_id" "uuid", "p_logged_method" "text", "p_food_name" "text", "p_weight_g" numeric, "p_calories" numeric, "p_protein" numeric, "p_carbs" numeric, "p_fat" numeric, "p_fiber" numeric, "p_sugar" numeric, "p_meal_period" "text", "p_image_url" "text", "p_food_id" "uuid", "p_serving_label" "text", "p_usda" "jsonb", "p_usda_fdc_claimed" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."log_meal_entry"("p_user_id" "uuid", "p_logged_method" "text", "p_food_name" "text", "p_weight_g" numeric, "p_calories" numeric, "p_protein" numeric, "p_carbs" numeric, "p_fat" numeric, "p_fiber" numeric, "p_sugar" numeric, "p_meal_period" "text", "p_image_url" "text", "p_food_id" "uuid", "p_serving_label" "text", "p_usda" "jsonb", "p_usda_fdc_claimed" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."log_workout_and_progress"("p_user_id" "uuid", "p_exercise" "text", "p_sets" integer, "p_reps" integer, "p_rep_quality_score" numeric, "p_workout_source" "text", "p_weight_kg" numeric, "p_duration_seconds" integer, "p_distance_m" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."log_workout_and_progress"("p_user_id" "uuid", "p_exercise" "text", "p_sets" integer, "p_reps" integer, "p_rep_quality_score" numeric, "p_workout_source" "text", "p_weight_kg" numeric, "p_duration_seconds" integer, "p_distance_m" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_verification_files_deleted"("p_application_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_verification_files_deleted"("p_application_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mission_damage"("p_base_damage" integer, "p_quality" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mission_damage"("p_base_damage" integer, "p_quality" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."missions_validate_publish"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."missions_validate_publish"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."pick_dungeon_exercise"("p_battle_id" "uuid", "p_run_id" "uuid", "p_ordinal" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."pick_dungeon_exercise"("p_battle_id" "uuid", "p_run_id" "uuid", "p_ordinal" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."ping_dungeon_progress"("p_user_id" "uuid", "p_battle_id" "uuid", "p_progress" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ping_dungeon_progress"("p_user_id" "uuid", "p_battle_id" "uuid", "p_progress" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."purchase_item"("p_user_id" "uuid", "p_item_key" "text", "p_quantity" integer, "p_request_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."purchase_item"("p_user_id" "uuid", "p_item_key" "text", "p_quantity" integer, "p_request_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."quit_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quit_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rate_plan_session"("p_user_id" "uuid", "p_plan_id" "uuid", "p_session_key" "text", "p_day" "date", "p_rating" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rate_plan_session"("p_user_id" "uuid", "p_plan_id" "uuid", "p_session_key" "text", "p_day" "date", "p_rating" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_admin_action"("p_actor_user_id" "uuid", "p_action" "text", "p_target_type" "text", "p_target_id" "text", "p_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_admin_action"("p_actor_user_id" "uuid", "p_action" "text", "p_target_type" "text", "p_target_id" "text", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_consent"("p_user_id" "uuid", "p_consent_type" "text", "p_notice_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_consent"("p_user_id" "uuid", "p_consent_type" "text", "p_notice_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_user_commodity_price"("p_user_id" "uuid", "p_commodity_slug" "text", "p_price_php" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_user_commodity_price"("p_user_id" "uuid", "p_commodity_slug" "text", "p_price_php" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."refresh_user_streak"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refresh_user_streak"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."refuse_price_history_update"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refuse_price_history_update"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."refuse_record_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refuse_record_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."replace_active_plan"("p_user_id" "uuid", "p_plan" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."replace_active_plan"("p_user_id" "uuid", "p_plan" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_specialization_affinity"("p_focus_type" "text", "p_exercise" "text", "p_primary_attribute" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_specialization_affinity"("p_focus_type" "text", "p_exercise" "text", "p_primary_attribute" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_specialization_rank"("p_focus_type" "text", "p_xp" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_specialization_rank"("p_focus_type" "text", "p_xp" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_coach_status"("p_user_id" "uuid", "p_actor_id" "uuid", "p_by_self" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_coach_status"("p_user_id" "uuid", "p_actor_id" "uuid", "p_by_self" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."roll_dungeon_reward"("p_event_id" "uuid", "p_user_id" "uuid", "p_seed" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."roll_dungeon_reward"("p_event_id" "uuid", "p_user_id" "uuid", "p_seed" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."search_foods"("p_query" "text", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."search_foods"("p_query" "text", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_plan_day_status"("p_user_id" "uuid", "p_plan_id" "uuid", "p_day" "date", "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_plan_day_status"("p_user_id" "uuid", "p_plan_id" "uuid", "p_day" "date", "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_relative_leaderboard"("p_user_id" "uuid", "p_opt_in" boolean, "p_notice_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_relative_leaderboard"("p_user_id" "uuid", "p_opt_in" boolean, "p_notice_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_training_limits"("p_user_id" "uuid", "p_areas" "text"[], "p_notice_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_training_limits"("p_user_id" "uuid", "p_areas" "text"[], "p_notice_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_user_budget"("p_user_id" "uuid", "p_daily_budget_php" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_user_budget"("p_user_id" "uuid", "p_daily_budget_php" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."settle_dungeon_time"("p_battle_id" "uuid", "p_caller_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."settle_dungeon_time"("p_battle_id" "uuid", "p_caller_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."settle_dungeon_victory"("p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."settle_dungeon_victory"("p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."spend_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid", "p_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."spend_gold"("p_user_id" "uuid", "p_amount" integer, "p_reason" "text", "p_source_id" "uuid", "p_idempotency_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_dungeon_battle"("p_user_id" "uuid", "p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_mission_attempt"("p_user_id" "uuid", "p_mission_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_mission_attempt"("p_user_id" "uuid", "p_mission_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."streak_restore_candidate"("p_user_id" "uuid", "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."streak_restore_candidate"("p_user_id" "uuid", "p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric, "p_workout_source" "text", "p_weight_kg" numeric, "p_assignment_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_dungeon_objective"("p_user_id" "uuid", "p_battle_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric, "p_workout_source" "text", "p_weight_kg" numeric, "p_assignment_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric, "p_workout_source" "text", "p_weight_kg" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_mission_objective"("p_user_id" "uuid", "p_attempt_id" "uuid", "p_achieved" numeric, "p_form_quality" numeric, "p_workout_source" "text", "p_weight_kg" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."training_history_counts"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."training_history_counts"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."use_item"("p_user_id" "uuid", "p_item_key" "text", "p_context_type" "text", "p_context_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."use_item"("p_user_id" "uuid", "p_item_key" "text", "p_context_type" "text", "p_context_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."withdraw_verification_application"("p_application_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."withdraw_verification_application"("p_application_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."admin_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."ai_suggestions" TO "anon";
GRANT ALL ON TABLE "public"."ai_suggestions" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_suggestions" TO "service_role";



GRANT ALL ON TABLE "public"."bosses" TO "anon";
GRANT ALL ON TABLE "public"."bosses" TO "authenticated";
GRANT ALL ON TABLE "public"."bosses" TO "service_role";



GRANT ALL ON TABLE "public"."bug_reports" TO "anon";
GRANT ALL ON TABLE "public"."bug_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."bug_reports" TO "service_role";



GRANT ALL ON TABLE "public"."chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_messages" TO "service_role";



GRANT ALL ON TABLE "public"."collectibles" TO "anon";
GRANT ALL ON TABLE "public"."collectibles" TO "authenticated";
GRANT ALL ON TABLE "public"."collectibles" TO "service_role";



GRANT ALL ON TABLE "public"."commodity_reference_prices" TO "service_role";



GRANT ALL ON TABLE "public"."direct_messages" TO "anon";
GRANT ALL ON TABLE "public"."direct_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."direct_messages" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_assignments" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_battles" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_battles" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_battles" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_clears" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_clears" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_clears" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_event_invites" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_event_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_event_invites" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_events" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_events" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_events" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_objective_results" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_objective_results" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_objective_results" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_reward_pool" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_reward_pool" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_reward_pool" TO "service_role";



GRANT ALL ON TABLE "public"."dungeon_runs" TO "anon";
GRANT ALL ON TABLE "public"."dungeon_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."dungeon_runs" TO "service_role";



GRANT ALL ON TABLE "public"."exercise_library" TO "service_role";



GRANT ALL ON TABLE "public"."exercises" TO "anon";
GRANT ALL ON TABLE "public"."exercises" TO "authenticated";
GRANT ALL ON TABLE "public"."exercises" TO "service_role";



GRANT ALL ON TABLE "public"."fitrack_logs" TO "anon";
GRANT ALL ON TABLE "public"."fitrack_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."fitrack_logs" TO "service_role";



GRANT ALL ON TABLE "public"."food_servings" TO "anon";
GRANT ALL ON TABLE "public"."food_servings" TO "authenticated";
GRANT ALL ON TABLE "public"."food_servings" TO "service_role";



GRANT ALL ON TABLE "public"."foods" TO "anon";
GRANT ALL ON TABLE "public"."foods" TO "authenticated";
GRANT ALL ON TABLE "public"."foods" TO "service_role";



GRANT ALL ON TABLE "public"."friendships" TO "anon";
GRANT ALL ON TABLE "public"."friendships" TO "authenticated";
GRANT ALL ON TABLE "public"."friendships" TO "service_role";



GRANT ALL ON TABLE "public"."game_config" TO "anon";
GRANT ALL ON TABLE "public"."game_config" TO "authenticated";
GRANT ALL ON TABLE "public"."game_config" TO "service_role";



GRANT ALL ON TABLE "public"."gold_ledger" TO "anon";
GRANT ALL ON TABLE "public"."gold_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."gold_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."gymmunity_posts" TO "anon";
GRANT ALL ON TABLE "public"."gymmunity_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."gymmunity_posts" TO "service_role";



GRANT ALL ON TABLE "public"."item_uses" TO "anon";
GRANT ALL ON TABLE "public"."item_uses" TO "authenticated";
GRANT ALL ON TABLE "public"."item_uses" TO "service_role";



GRANT ALL ON TABLE "public"."market_commodities" TO "service_role";



GRANT ALL ON TABLE "public"."mission_attempts" TO "anon";
GRANT ALL ON TABLE "public"."mission_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."mission_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."mission_chapters" TO "anon";
GRANT ALL ON TABLE "public"."mission_chapters" TO "authenticated";
GRANT ALL ON TABLE "public"."mission_chapters" TO "service_role";



GRANT ALL ON TABLE "public"."mission_clears" TO "anon";
GRANT ALL ON TABLE "public"."mission_clears" TO "authenticated";
GRANT ALL ON TABLE "public"."mission_clears" TO "service_role";



GRANT ALL ON TABLE "public"."mission_objective_results" TO "anon";
GRANT ALL ON TABLE "public"."mission_objective_results" TO "authenticated";
GRANT ALL ON TABLE "public"."mission_objective_results" TO "service_role";



GRANT ALL ON TABLE "public"."mission_objectives" TO "anon";
GRANT ALL ON TABLE "public"."mission_objectives" TO "authenticated";
GRANT ALL ON TABLE "public"."mission_objectives" TO "service_role";



GRANT ALL ON TABLE "public"."missions" TO "anon";
GRANT ALL ON TABLE "public"."missions" TO "authenticated";
GRANT ALL ON TABLE "public"."missions" TO "service_role";



GRANT ALL ON TABLE "public"."privacy_export_coverage" TO "service_role";



GRANT ALL ON TABLE "public"."privacy_notices" TO "service_role";



GRANT ALL ON TABLE "public"."rank_history" TO "anon";
GRANT ALL ON TABLE "public"."rank_history" TO "authenticated";
GRANT ALL ON TABLE "public"."rank_history" TO "service_role";



GRANT ALL ON TABLE "public"."rank_thresholds" TO "anon";
GRANT ALL ON TABLE "public"."rank_thresholds" TO "authenticated";
GRANT ALL ON TABLE "public"."rank_thresholds" TO "service_role";



GRANT ALL ON TABLE "public"."rarities" TO "anon";
GRANT ALL ON TABLE "public"."rarities" TO "authenticated";
GRANT ALL ON TABLE "public"."rarities" TO "service_role";



GRANT ALL ON TABLE "public"."rate_limits" TO "anon";
GRANT ALL ON TABLE "public"."rate_limits" TO "authenticated";
GRANT ALL ON TABLE "public"."rate_limits" TO "service_role";



GRANT ALL ON TABLE "public"."routine_exercises" TO "anon";
GRANT ALL ON TABLE "public"."routine_exercises" TO "authenticated";
GRANT ALL ON TABLE "public"."routine_exercises" TO "service_role";



GRANT ALL ON TABLE "public"."routines" TO "anon";
GRANT ALL ON TABLE "public"."routines" TO "authenticated";
GRANT ALL ON TABLE "public"."routines" TO "service_role";



GRANT ALL ON TABLE "public"."shop_items" TO "anon";
GRANT ALL ON TABLE "public"."shop_items" TO "authenticated";
GRANT ALL ON TABLE "public"."shop_items" TO "service_role";



GRANT ALL ON TABLE "public"."shop_purchases" TO "anon";
GRANT ALL ON TABLE "public"."shop_purchases" TO "authenticated";
GRANT ALL ON TABLE "public"."shop_purchases" TO "service_role";



GRANT ALL ON TABLE "public"."specialization_affinity" TO "anon";
GRANT ALL ON TABLE "public"."specialization_affinity" TO "authenticated";
GRANT ALL ON TABLE "public"."specialization_affinity" TO "service_role";



GRANT ALL ON TABLE "public"."streak_shields" TO "anon";
GRANT ALL ON TABLE "public"."streak_shields" TO "authenticated";
GRANT ALL ON TABLE "public"."streak_shields" TO "service_role";



GRANT ALL ON TABLE "public"."strength_records" TO "anon";
GRANT ALL ON TABLE "public"."strength_records" TO "authenticated";
GRANT ALL ON TABLE "public"."strength_records" TO "service_role";



GRANT ALL ON TABLE "public"."strength_prs" TO "service_role";



GRANT ALL ON TABLE "public"."threat_ranks" TO "anon";
GRANT ALL ON TABLE "public"."threat_ranks" TO "authenticated";
GRANT ALL ON TABLE "public"."threat_ranks" TO "service_role";



GRANT ALL ON TABLE "public"."training_limits" TO "service_role";



GRANT ALL ON TABLE "public"."training_plan_days" TO "service_role";



GRANT ALL ON TABLE "public"."training_plan_feedback" TO "service_role";



GRANT ALL ON TABLE "public"."training_plans" TO "service_role";



GRANT ALL ON TABLE "public"."training_surveys" TO "service_role";



GRANT ALL ON TABLE "public"."user_budget_settings" TO "service_role";



GRANT ALL ON TABLE "public"."user_collectibles" TO "anon";
GRANT ALL ON TABLE "public"."user_collectibles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_collectibles" TO "service_role";



GRANT ALL ON TABLE "public"."user_commodity_prices" TO "service_role";



GRANT ALL ON TABLE "public"."user_consents" TO "service_role";



GRANT ALL ON TABLE "public"."user_exercise_templates" TO "anon";
GRANT ALL ON TABLE "public"."user_exercise_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."user_exercise_templates" TO "service_role";



GRANT ALL ON TABLE "public"."user_inventory" TO "anon";
GRANT ALL ON TABLE "public"."user_inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."user_inventory" TO "service_role";



GRANT ALL ON TABLE "public"."user_reports" TO "anon";
GRANT ALL ON TABLE "public"."user_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."user_reports" TO "service_role";



GRANT ALL ON TABLE "public"."user_specialization_xp" TO "anon";
GRANT ALL ON TABLE "public"."user_specialization_xp" TO "authenticated";
GRANT ALL ON TABLE "public"."user_specialization_xp" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."verification_applications" TO "service_role";



GRANT ALL ON TABLE "public"."workout_logs" TO "anon";
GRANT ALL ON TABLE "public"."workout_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."workout_logs" TO "service_role";



GRANT ALL ON TABLE "public"."xp_config" TO "anon";
GRANT ALL ON TABLE "public"."xp_config" TO "authenticated";
GRANT ALL ON TABLE "public"."xp_config" TO "service_role";



GRANT ALL ON TABLE "public"."xp_grants" TO "anon";
GRANT ALL ON TABLE "public"."xp_grants" TO "authenticated";
GRANT ALL ON TABLE "public"."xp_grants" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";









-- Storage buckets used by the Edge Functions (files are read/written only with the service role).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('gymmunity-images', 'gymmunity-images', TRUE, 2097152, ARRAY['image/jpeg']),
  ('verification-evidence', 'verification-evidence', FALSE, 2097152, ARRAY['image/jpeg']),
  ('exercise-media', 'exercise-media', FALSE, 524288, ARRAY['image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;
