-- AWXCEND reference data (game configuration, not user data), copied 2026-09-26.
-- Allow-listed tables only: exercises, xp_config, rank_thresholds, specialization_affinity, game_config,
-- privacy_notices, privacy_export_coverage, foods, food_servings, threat_ranks, rarities, shop_items,
-- collectibles, missions, mission_chapters, mission_objectives, bosses, market_commodities,
-- commodity_reference_prices. Excluded on purpose: every user-owned table, dungeon data (admin-created),
-- and exercise_library (RepDB data; its licence requires separate permission/credit).

SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

-- \restrict iB88aUzwRbXrZ42y34qOFq6XA9ZTV52Vvef3UrP5ezCGW6nNftweuWXE5B9z6HJ

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: bosses; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."bosses" ("id", "key", "name", "art_key", "lore", "created_at") VALUES
	('0d507c24-2aff-4058-90d4-569f008e9305', 'rust_gremlin', 'Rust Gremlin', NULL, 'A scrap-metal pest that guards the gate. It only respects effort.', '2026-09-11 14:15:20.685903+00'),
	('bf6a5c26-63ab-4a5b-9237-dfc462c27c86', 'slick_ogre', 'Slick Ogre', NULL, 'Slow, heavy, and impossible to out-muscle. Out-last it instead.', '2026-09-11 14:15:20.685903+00'),
	('42794266-0162-4341-ab69-4bb4702ef967', 'iron_hound', 'Iron Hound', NULL, 'It circles until you stop moving. So do not stop moving.', '2026-09-11 14:15:20.685903+00'),
	('af593e96-fc24-40b7-8c77-98ff886871c4', 'ash_wraith', 'Ash Wraith', NULL, 'Born of quit attempts. It feeds on the set you did not finish.', '2026-09-11 14:15:20.685903+00'),
	('9a0b5530-3e9f-49b6-ab00-975f477e464f', 'stone_sentinel', 'Stone Sentinel', NULL, 'It has stood for a thousand days. Outwork it for one.', '2026-09-11 14:15:20.685903+00'),
	('c389fbc4-c8e5-48d9-8992-b33e6d8fe120', 'sand_reaver', 'Sand Reaver', NULL, 'Strikes in flurries. Answer in flurries.', '2026-09-11 14:15:20.685903+00'),
	('67735ee6-9bac-4833-ba20-d55e2dbadc38', 'frost_revenant', 'Frost Revenant', NULL, 'The cold rewards whoever holds position longest.', '2026-09-11 14:15:20.685903+00'),
	('c8e69931-d75e-4aee-9f18-a6838ad15d83', 'crimson_warden', 'Crimson Warden', NULL, 'Guards the last door before the deep. Legs decide this one.', '2026-09-11 14:15:20.685903+00'),
	('4d609640-a3dc-4482-8d59-b42ec3a9b856', 'void_stalker', 'Void Stalker', NULL, 'It mirrors your weakest lift. Bring all of them.', '2026-09-11 14:15:20.685903+00'),
	('99f2c619-df03-4c24-8244-75fd9efb3910', 'abyss_monarch', 'Abyss Monarch', NULL, 'The chapter''s end. Everything the gate taught you, at once.', '2026-09-11 14:15:20.685903+00'),
	('12ca6378-000c-4064-9469-72cfb23d4c69', 'dungeon_f2bd1a74', 'the creation', NULL, 'no info', '2026-09-12 16:19:31.339613+00'),
	('535e9c82-85f1-4c7c-8880-2069c4461b6a', 'dungeon_d8f4dd98', 'Probe 1790393615854', NULL, NULL, '2026-09-26 03:33:36.884225+00'),
	('3020c80c-aedc-4273-8e66-492321bd26a7', 'dungeon_24105838', 'Probe 1790393660014', NULL, NULL, '2026-09-26 03:34:19.941683+00');


--
-- Data for Name: rarities; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."rarities" ("key", "label", "sort_order", "color") VALUES
	('common', 'Common', 1, '#9aa8c7'),
	('rare', 'Rare', 2, '#2b8cff'),
	('epic', 'Epic', 3, '#b57bff'),
	('legendary', 'Legendary', 4, '#fbbf24'),
	('mythic', 'Mythic', 5, '#ff3b4f');


--
-- Data for Name: collectibles; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."collectibles" ("id", "key", "kind", "name", "description", "rarity", "gold_value", "is_active", "created_at") VALUES
	('d0001fbc-1e56-445d-a7eb-8bafab3e2749', 'title_gatebreaker', 'title', 'Gatebreaker', 'For closing a gate that was opened against you.', 'common', 120, true, '2026-09-12 15:32:49.080569+00'),
	('033304d4-630c-4626-a511-f809a0ab9c87', 'title_deep_walker', 'title', 'Deep Walker', 'Awarded for clearing a Dungeon at rank A or above.', 'rare', 300, true, '2026-09-12 15:32:49.080569+00'),
	('54a5ef4a-6a1b-49f9-89de-f70e69b40adc', 'title_monarch', 'title', 'Monarch of Nothing', 'Only an anomalous gate gives this one up.', 'legendary', 900, true, '2026-09-12 15:32:49.080569+00'),
	('5b834678-864a-4815-858f-a7b9c10128bc', 'badge_first_light', 'badge', 'First Light', 'The first gate you ever closed.', 'common', 80, true, '2026-09-12 15:32:49.080569+00'),
	('b17e8fd0-6fdb-46c5-964b-a586f4854ec3', 'badge_shield_bearer', 'badge', 'Shield Bearer', 'For carrying a party through a Dungeon.', 'rare', 260, true, '2026-09-12 15:32:49.080569+00'),
	('5be19e9d-dea8-4e0e-959c-5fad454c2ea6', 'badge_unbroken', 'badge', 'Unbroken', 'Cleared a Dungeon without ever going down.', 'epic', 520, true, '2026-09-12 15:32:49.080569+00'),
	('0201bfcd-7dcb-491b-91ea-2f4a59c95f71', 'badge_abyss_mark', 'badge', 'Mark of the Abyss', 'Something in an X-rank gate left this on you.', 'mythic', 1400, true, '2026-09-12 15:32:49.080569+00');


--
-- Data for Name: foods; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."foods" ("id", "slug", "name", "local_names", "aliases", "category", "region", "preparation", "brand", "calories", "protein", "carbs", "fat", "fiber", "sugar", "source", "source_reference", "is_estimate", "estimate_note", "active", "search_text", "created_at", "updated_at", "description") VALUES
	('1501d314-f8c5-442f-99dd-f77bedd1d7ee', 'egg-hard-boiled', 'Hard-boiled egg', '{"Nilagang itlog"}', '{itlog,"boiled egg",egg}', 'generic', 'ph', 'boiled', NULL, 155.0, 12.6, 1.1, 10.6, 0.0, 1.1, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173424 "Egg, whole, cooked, hard-boiled"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Egg, whole, cooked, hard-boiled" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'hard-boiled egg nilagang itlog itlog boiled egg egg', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('114cfa66-bd83-4a15-9724-41efcd8d8117', 'rice-white-cooked', 'Cooked white rice', '{Kanin}', '{rice,"plain rice","steamed rice"}', 'generic', 'ph', 'boiled', NULL, 130.0, 2.7, 28.2, 0.3, 0.4, 0.1, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 168878 "Rice, white, long-grain, regular, enriched, cooked"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Rice, white, long-grain, regular, enriched, cooked" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'cooked white rice kanin rice plain rice steamed rice', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('f5f921ae-950f-4221-99f2-6792af139895', 'rice-garlic-fried', 'Garlic fried rice', '{Sinangag}', '{"fried rice","garlic rice"}', 'generic', 'ph', 'fried', NULL, 160.2, 2.6, 27.0, 4.3, 0.4, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release); per 100 g: 96 g FDC 168878 "Rice, white, long-grain, regular, enriched, cooked" + 4 g FDC 171411 "Oil, soybean, salad or cooking"', true, 'Estimate derived from USDA SR Legacy values using a preparation assumption. Assumes 96 g cooked white rice (USDA FDC 168878) fried with 4 g soybean oil (USDA FDC 171411) per 100 g; garlic treated as negligible. Not measured Philippine data.', true, 'garlic fried rice sinangag fried rice garlic rice', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('ba1aa323-69e2-4c0f-8322-c7e0d08c6cb1', 'rice-porridge', 'Plain rice porridge', '{Lugaw}', '{"arroz caldo",congee,porridge}', 'generic', 'ph', 'boiled', NULL, 65.0, 1.3, 14.1, 0.1, 0.2, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release); per 100 g: 50 g FDC 168878 "Rice, white, long-grain, regular, enriched, cooked" + water', true, 'Estimate derived from USDA SR Legacy values using a preparation assumption. Assumes plain lugaw is 50 g cooked white rice (USDA FDC 168878) to 50 g water per 100 g, with no chicken, egg or toppings. Thicker or thinner lugaw changes every value. Not measured Philippine data.', true, 'plain rice porridge lugaw arroz caldo congee porridge', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('77cbe759-e2ea-47d7-9162-25308a97e799', 'pandesal', 'Pandesal (bread roll)', '{Pandesal,"Pan de sal"}', '{"bread roll",pandisal}', 'generic', 'ph', 'baked', NULL, 310.0, 10.9, 52.0, 6.5, 2.0, 5.6, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 172793 "Rolls, dinner, plain, commercially prepared (includes brown-and-serve)"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Rolls, dinner, plain, commercially prepared (includes brown-and-serve)" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Proxy: pandesal is estimated with USDA commercial plain dinner rolls; recipes and roll size vary.', true, 'pandesal (bread roll) pandesal pan de sal bread roll pandisal', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('0ae8a0ec-8a5f-4397-9904-38ff64f0c49b', 'white-bread', 'White bread', '{Tinapay}', '{"loaf bread","sliced bread"}', 'generic', 'ph', 'baked', NULL, 266.0, 8.9, 49.4, 3.3, 2.7, 5.7, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 174924 "Bread, white, commercially prepared (includes soft bread crumbs)"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Bread, white, commercially prepared (includes soft bread crumbs)" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'white bread tinapay loaf bread sliced bread', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('c74edb71-3f07-47f0-9b20-e0a127efdcbd', 'tofu-firm', 'Firm tofu', '{Tokwa}', '{tofu,tokua}', 'ingredient', 'ph', 'raw', NULL, 144.0, 17.3, 2.8, 8.7, 2.3, NULL, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 172475 "Tofu, raw, firm, prepared with calcium sulfate"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Tofu, raw, firm, prepared with calcium sulfate" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'firm tofu tokwa tofu tokua', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('59fb3334-693b-48f4-9b73-0be9344ae828', 'tofu-fried', 'Fried tofu', '{"Pritong tokwa"}', '{tokwa,tofu,tokua}', 'generic', 'ph', 'fried', NULL, 270.0, 18.8, 8.9, 20.2, 3.9, 2.7, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 172451 "Tofu, fried"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Tofu, fried" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'fried tofu pritong tokwa tokwa tofu tokua', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('3dd60dac-9fe4-4418-9cdf-ea9e725cebf1', 'mussels-boiled', 'Boiled mussels', '{"Nilagang tahong"}', '{tahong,mussels}', 'generic', 'ph', 'boiled', NULL, 172.0, 23.8, 7.4, 4.5, 0.0, NULL, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 174217 "Mollusks, mussel, blue, cooked, moist heat"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Mollusks, mussel, blue, cooked, moist heat" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Proxy: USDA blue mussels stand in for local green mussels (tahong).', true, 'boiled mussels nilagang tahong tahong mussels', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('3456809d-e83e-417e-8c13-8acdcf7dc9aa', 'shrimp-boiled', 'Boiled shrimp', '{"Nilagang hipon"}', '{hipon,shrimp,prawns}', 'generic', 'ph', 'boiled', NULL, 99.0, 24.0, 0.2, 0.3, NULL, NULL, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 175180 "Crustaceans, shrimp, cooked"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Crustaceans, shrimp, cooked" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'boiled shrimp nilagang hipon hipon shrimp prawns', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('52c4c04a-82aa-4e44-9ae9-d19c55eac323', 'tilapia-grilled', 'Grilled tilapia', '{"Inihaw na tilapia"}', '{tilapia}', 'generic', 'ph', 'grilled', NULL, 128.0, 26.2, 0.0, 2.7, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 175177 "Fish, tilapia, cooked, dry heat"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Fish, tilapia, cooked, dry heat" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. USDA "cooked, dry heat" is used for grilled; charring and basting are not accounted for.', true, 'grilled tilapia inihaw na tilapia tilapia', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('130a6575-1278-4dab-9350-ef79387b1983', 'tilapia-fried', 'Fried tilapia', '{"Pritong tilapia"}', '{tilapia}', 'generic', 'ph', 'fried', NULL, 165.8, 24.8, 0.0, 7.5, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release); per 100 g: 95 g FDC 175177 "Fish, tilapia, cooked, dry heat" + 5 g FDC 171411 "Oil, soybean, salad or cooking"', true, 'Estimate derived from USDA SR Legacy values using a preparation assumption. Assumes 95 g tilapia cooked by dry heat (USDA FDC 175177) plus 5 g absorbed soybean oil (USDA FDC 171411) per 100 g; pan-fried, not breaded. Oil absorption varies widely. Not measured Philippine data.', true, 'fried tilapia pritong tilapia tilapia', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('26172cb6-0562-458e-b941-6a4783e3ff87', 'milkfish-grilled', 'Grilled milkfish', '{"Inihaw na bangus"}', '{bangus,bangos,milkfish}', 'generic', 'ph', 'grilled', NULL, 190.0, 26.3, 0.0, 8.6, 0.0, NULL, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 171995 "Fish, milkfish, cooked, dry heat"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Fish, milkfish, cooked, dry heat" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. USDA "cooked, dry heat" is used for grilled.', true, 'grilled milkfish inihaw na bangus bangus bangos milkfish', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('6bdffe19-be4b-4d2c-ab23-7a335f74d738', 'milkfish-fried', 'Fried milkfish', '{"Pritong bangus"}', '{bangus,bangos,"daing na bangus",milkfish}', 'generic', 'ph', 'fried', NULL, 224.7, 25.0, 0.0, 13.2, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release); per 100 g: 95 g FDC 171995 "Fish, milkfish, cooked, dry heat" + 5 g FDC 171411 "Oil, soybean, salad or cooking"', true, 'Estimate derived from USDA SR Legacy values using a preparation assumption. Assumes 95 g milkfish cooked by dry heat (USDA FDC 171995) plus 5 g absorbed soybean oil (USDA FDC 171411) per 100 g; marinade (daing) not included. Not measured Philippine data.', true, 'fried milkfish pritong bangus bangus bangos daing na bangus milkfish', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('3b9ea4d5-7a63-4f38-9005-3b41f8859895', 'round-scad-fried', 'Fried round scad', '{"Pritong galunggong"}', '{galunggong,GG}', 'generic', 'ph', 'fried', NULL, 235.2, 24.4, 0.0, 14.6, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release); per 100 g: 95 g FDC 171994 "Fish, mackerel, Pacific and jack, mixed species, cooked, dry heat" + 5 g FDC 171411 "Oil, soybean, salad or cooking"', true, 'Estimate derived from USDA SR Legacy values using a preparation assumption. Proxy species: USDA has no round scad, so Pacific and jack mackerel cooked by dry heat (USDA FDC 171994) is used — 95 g plus 5 g absorbed soybean oil (USDA FDC 171411) per 100 g. Not measured Philippine data.', true, 'fried round scad pritong galunggong galunggong gg', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('6d1eacd3-9624-4c9d-af65-de67dbfcefc3', 'sardines-tomato-canned', 'Canned sardines in tomato sauce', '{Sardinas}', '{sardines,"sardinas de lata"}', 'generic', 'ph', 'canned', NULL, 185.0, 20.9, 0.5, 10.5, 0.1, 0.4, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 175140 "Fish, sardine, Pacific, canned in tomato sauce, drained solids with bone"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Fish, sardine, Pacific, canned in tomato sauce, drained solids with bone" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Drained solids with bone, per USDA; local brands differ in sauce and oil.', true, 'canned sardines in tomato sauce sardinas sardines sardinas de lata', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('de407ef7-d4c7-422f-959b-ad8a57bb7668', 'tuna-canned-water', 'Canned tuna in water', '{"Tuna de lata"}', '{tuna,"tuna flakes"}', 'generic', 'international', 'canned', NULL, 86.0, 19.4, 0.0, 1.0, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173709 "Fish, tuna, light, canned in water, drained solids (Includes foods for USDA''s Food Distribution Program)"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Fish, tuna, light, canned in water, drained solids (Includes foods for USDA''s Food Distribution Program)" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'canned tuna in water tuna de lata tuna tuna flakes', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('3aa588dd-8cc2-403d-a172-ab288500b70c', 'chicken-breast-grilled', 'Grilled chicken breast (skinless)', '{"Inihaw na dibdib ng manok"}', '{"chicken breast",manok,"grilled chicken"}', 'generic', 'ph', 'grilled', NULL, 151.0, 30.5, 0.0, 3.2, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 171534 "Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, grilled"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, grilled" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'grilled chicken breast (skinless) inihaw na dibdib ng manok chicken breast manok grilled chicken', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('d2a88788-3225-4ed5-ae87-6a21740c8f3c', 'chicken-leg-grilled', 'Grilled chicken leg (with skin)', '{"Inihaw na manok"}', '{"chicken inasal",manok,"grilled chicken","chicken leg"}', 'generic', 'ph', 'grilled', NULL, 184.0, 24.0, 0.0, 9.0, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173617 "Chicken, broilers or fryers, leg, meat and skin, cooked, roasted"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Chicken, broilers or fryers, leg, meat and skin, cooked, roasted" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. USDA roasted chicken leg with skin is used for grilled; inasal marinade and basting oil are not included.', true, 'grilled chicken leg (with skin) inihaw na manok chicken inasal manok grilled chicken chicken leg', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('1a79b37a-2abd-40da-8846-b3ad660c0b4c', 'pork-belly-grilled', 'Grilled pork belly', '{"Inihaw na liempo"}', '{liempo,"pork belly"}', 'generic', 'ph', 'grilled', NULL, 361.0, 20.9, 0.0, 30.9, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169178 "Pork, fresh, spareribs, separable lean and fat, cooked, roasted"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Pork, fresh, spareribs, separable lean and fat, cooked, roasted" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Proxy cut: USDA has no cooked pork belly, so roasted spareribs (lean and fat) are used. Liempo is usually fattier, so calories and fat are likely UNDERestimated.', true, 'grilled pork belly inihaw na liempo liempo pork belly', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('08ac9626-d4ca-43b9-9e3b-c59aacc025fe', 'pork-ground-cooked', 'Cooked ground pork', '{"Giniling na baboy"}', '{giniling,"ground pork"}', 'ingredient', 'ph', 'cooked', NULL, 297.0, 25.7, 0.0, 20.8, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 167903 "Pork, fresh, ground, cooked"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Pork, fresh, ground, cooked" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'cooked ground pork giniling na baboy giniling ground pork', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('dcbb1cef-d7e6-4810-945d-dab0ecc29329', 'beef-ground-cooked', 'Cooked ground beef (80% lean)', '{"Giniling na baka"}', '{giniling,"ground beef"}', 'ingredient', 'ph', 'cooked', NULL, 272.0, 27.0, 0.0, 17.4, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 171799 "Beef, ground, 80% lean meat / 20% fat, crumbles, cooked, pan-browned"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Beef, ground, 80% lean meat / 20% fat, crumbles, cooked, pan-browned" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'cooked ground beef (80% lean) giniling na baka giniling ground beef', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('2316ce39-c5ce-45ac-ba1e-ef5b49b511d8', 'corned-beef-canned', 'Canned corned beef', '{"Corned beef de lata"}', '{"corned beef","karne norte"}', 'generic', 'ph', 'canned', NULL, 250.0, 27.1, 0.0, 14.9, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 170602 "Beef, cured, corned beef, canned"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Beef, cured, corned beef, canned" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'canned corned beef corned beef de lata corned beef karne norte', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('f39dfb88-a3bb-45e2-9d4e-cfef1235d763', 'mung-beans-boiled', 'Boiled mung beans', '{"Nilagang monggo"}', '{monggo,mongo,"mung beans"}', 'ingredient', 'ph', 'boiled', NULL, 105.0, 7.0, 19.2, 0.4, 7.6, 2.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 174257 "Mung beans, mature seeds, cooked, boiled, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Mung beans, mature seeds, cooked, boiled, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Plain boiled beans only — ginisang monggo with pork, oil or leaves is a mixed dish and is not included.', true, 'boiled mung beans nilagang monggo monggo mongo mung beans', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('586cc9b3-a030-4684-8cf7-2e4014520c64', 'water-spinach-boiled', 'Boiled water spinach', '{Kangkong}', '{kangkong,"water spinach","swamp cabbage"}', 'generic', 'ph', 'boiled', NULL, 20.0, 2.1, 3.7, 0.2, 1.9, NULL, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169302 "Water convolvulus, cooked, boiled, drained, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Water convolvulus, cooked, boiled, drained, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'boiled water spinach kangkong kangkong water spinach swamp cabbage', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('80a2f6dd-215c-4144-b400-347089898d34', 'pechay-boiled', 'Boiled bok choy', '{Pechay}', '{petsay,"bok choy",pechay}', 'generic', 'ph', 'boiled', NULL, 12.0, 1.6, 1.8, 0.2, 1.0, 0.8, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 170391 "Cabbage, chinese (pak-choi), cooked, boiled, drained, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Cabbage, chinese (pak-choi), cooked, boiled, drained, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'boiled bok choy pechay petsay bok choy pechay', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('b69ab694-9002-4fa8-aaa6-3cbac8f7ba0c', 'yardlong-beans-boiled', 'Boiled string beans', '{Sitaw}', '{sitaw,"string beans","yardlong beans"}', 'generic', 'ph', 'boiled', NULL, 47.0, 2.5, 9.2, 0.1, NULL, NULL, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169223 "Yardlong bean, cooked, boiled, drained, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Yardlong bean, cooked, boiled, drained, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'boiled string beans sitaw sitaw string beans yardlong beans', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('954f214f-3a8d-47fc-bd1c-459fa98d358c', 'squash-boiled', 'Boiled squash', '{Kalabasa}', '{kalabasa,squash,pumpkin}', 'generic', 'ph', 'boiled', NULL, 20.0, 0.7, 4.9, 0.1, 1.1, 2.1, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 168449 "Pumpkin, cooked, boiled, drained, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Pumpkin, cooked, boiled, drained, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Proxy: USDA boiled pumpkin stands in for local kalabasa.', true, 'boiled squash kalabasa kalabasa squash pumpkin', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('db350d9d-01b8-41e5-bc31-d43daf5eee4f', 'eggplant-boiled', 'Boiled eggplant', '{"Nilagang talong"}', '{talong,eggplant}', 'generic', 'ph', 'boiled', NULL, 35.0, 0.8, 8.7, 0.2, 2.5, 3.2, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169229 "Eggplant, cooked, boiled, drained, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Eggplant, cooked, boiled, drained, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'boiled eggplant nilagang talong talong eggplant', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('f6e218d1-86ed-4f84-bc58-bc2e8e36e777', 'sweet-potato-boiled', 'Boiled sweet potato', '{"Nilagang kamote"}', '{kamote,"sweet potato"}', 'generic', 'ph', 'boiled', NULL, 76.0, 1.4, 17.7, 0.1, 2.5, 5.7, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 168484 "Sweet potato, cooked, boiled, without skin"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Sweet potato, cooked, boiled, without skin" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'boiled sweet potato nilagang kamote kamote sweet potato', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('a93c1ec1-5b4a-4530-bcce-37fc33d04494', 'saba-banana-boiled', 'Boiled saba banana', '{"Nilagang saging saba"}', '{saba,saging,"cooking banana"}', 'generic', 'ph', 'boiled', NULL, 121.0, 1.1, 29.2, 0.1, 2.6, 2.3, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 168216 "Plantains, green, boiled"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Plantains, green, boiled" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Proxy: USDA boiled green plantain stands in for saba; ripe saba is sweeter, so sugar is likely underestimated.', true, 'boiled saba banana nilagang saging saba saba saging cooking banana', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('e8fe75b1-c8e6-4168-86e0-dd0698dff2c1', 'banana-raw', 'Banana', '{"Saging (lakatan / latundan)"}', '{saging,lakatan,latundan,banana}', 'generic', 'ph', 'raw', NULL, 89.0, 1.1, 22.8, 0.3, 2.6, 12.2, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173944 "Bananas, raw"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Bananas, raw" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'banana saging (lakatan / latundan) saging lakatan latundan banana', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('884014ad-5332-444a-9289-736ddc74a1dc', 'mango-ripe', 'Ripe mango', '{"Hinog na mangga"}', '{mangga,mango}', 'generic', 'ph', 'raw', NULL, 60.0, 0.8, 15.0, 0.4, 1.6, 13.7, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169910 "Mangos, raw"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Mangos, raw" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. USDA mangoes are mostly non-Philippine varieties; carabao mango sweetness differs.', true, 'ripe mango hinog na mangga mangga mango', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('72d1adb0-e8e1-418a-85f7-1ffe1c178e7a', 'papaya-raw', 'Papaya', '{Papaya}', '{papaya}', 'generic', 'ph', 'raw', NULL, 43.0, 0.5, 10.8, 0.3, 1.7, 7.8, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169926 "Papayas, raw"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Papayas, raw" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'papaya papaya papaya', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('6b8105dd-e0c5-4780-8fd7-080484632c74', 'pineapple-raw', 'Pineapple', '{Pinya}', '{pinya,pineapple}', 'generic', 'ph', 'raw', NULL, 50.0, 0.5, 13.1, 0.1, 1.4, 9.9, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169124 "Pineapple, raw, all varieties"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Pineapple, raw, all varieties" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'pineapple pinya pinya pineapple', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('be40521e-a893-42ac-9981-a154ea37ca22', 'peanuts-roasted', 'Dry-roasted peanuts', '{Mani}', '{mani,peanuts}', 'generic', 'ph', 'baked', NULL, 587.0, 24.4, 21.3, 49.7, 8.4, 4.9, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173806 "Peanuts, all types, dry-roasted, without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Peanuts, all types, dry-roasted, without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Dry-roasted, unsalted; adobong mani fried in oil with garlic is higher in fat.', true, 'dry-roasted peanuts mani mani peanuts', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('916c00c7-68f0-4ff6-9435-90d5430ede75', 'coconut-milk', 'Coconut milk', '{Gata}', '{gata,"kakang gata","coconut milk"}', 'ingredient', 'ph', 'raw', NULL, 230.0, 2.3, 5.5, 23.8, 2.2, 3.3, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 170172 "Nuts, coconut milk, raw (liquid expressed from grated meat and water)"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Nuts, coconut milk, raw (liquid expressed from grated meat and water)" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation. Liquid pressed from grated coconut and water; kakang gata (first press) is richer.', true, 'coconut milk gata gata kakang gata coconut milk', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('56c6804c-10c9-4dd5-81dd-77d0d5f9c42f', 'milk-whole', 'Whole milk', '{Gatas}', '{gatas,"fresh milk",milk}', 'generic', 'international', 'raw', NULL, 61.0, 3.2, 4.8, 3.3, 0.0, 5.1, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 172217 "Milk, whole, 3.25% milkfat, without added vitamin A and vitamin D"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Milk, whole, 3.25% milkfat, without added vitamin A and vitamin D" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'whole milk gatas gatas fresh milk milk', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('f229f4f2-a4d5-4f97-bb83-cea1e103fcfc', 'oatmeal-cooked', 'Cooked oatmeal (with water)', '{Oatmeal}', '{oats,oatmeal,otmil}', 'generic', 'international', 'boiled', NULL, 71.0, 2.5, 12.0, 1.5, 1.7, 0.3, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173905 "Cereals, oats, regular and quick, unenriched, cooked with water (includes boiling and microwaving), without salt"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Cereals, oats, regular and quick, unenriched, cooked with water (includes boiling and microwaving), without salt" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'cooked oatmeal (with water) oatmeal oats oatmeal otmil', '2026-09-17 08:42:48.171398+00', '2026-09-17 08:42:48.171398+00', NULL),
	('382861da-2cda-477d-9583-fb917dad048a', 'egg-raw', 'Raw egg', '{"Itlog (hilaw)"}', '{itlog,egg}', 'ingredient', 'ph', 'raw', NULL, 143.0, 12.6, 0.7, 9.5, 0.0, 0.4, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 171287 "Egg, whole, raw, fresh"', true, 'Nutrition per 100 g of egg without the shell is USDA SR Legacy data for "Egg, whole, raw, fresh" (US samples). Used as an estimate for eggs bought in the Philippines — not measured Philippine data.', true, 'raw egg itlog (hilaw) itlog egg', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('5d6facd3-feaa-4e69-921f-4f3fb3e28d53', 'chicken-whole-raw', 'Whole chicken, raw (meat and skin)', '{"Manok (hilaw)"}', '{manok,chicken,"whole chicken"}', 'ingredient', 'ph', 'raw', NULL, 215.0, 18.6, 0.0, 15.1, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 171447 "Chicken, broilers or fryers, meat and skin, raw"', true, 'Nutrition per 100 g of meat and skin (no bone) is USDA SR Legacy data for "Chicken, broilers or fryers, meat and skin, raw" (US broilers). Used as an estimate for chicken bought in the Philippines — not measured Philippine data.', true, 'whole chicken, raw (meat and skin) manok (hilaw) manok chicken whole chicken', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('af4a3b2e-14cf-4b5b-af44-cec0f76060b5', 'chicken-breast-raw', 'Chicken breast, raw (skinless, boneless)', '{"Pitso ng manok (hilaw)"}', '{"dibdib ng manok","chicken breast",manok}', 'ingredient', 'ph', 'raw', NULL, 120.0, 22.5, 0.0, 2.6, 0.0, 0.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 171077 "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw" (US broilers). Used as an estimate for chicken breast fillet bought in the Philippines — not measured Philippine data.', true, 'chicken breast, raw (skinless, boneless) pitso ng manok (hilaw) dibdib ng manok chicken breast manok', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('42c12560-2048-4a85-9b81-0f72ebb1599c', 'mung-beans-dried', 'Dried mung beans', '{"Munggo (tuyo)"}', '{munggo,monggo,"mung beans"}', 'ingredient', 'ph', 'dried', NULL, 347.0, 23.9, 62.6, 1.2, 16.3, 6.6, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 174256 "Mung beans, mature seeds, raw"', true, 'Nutrition per 100 g of dry, uncooked beans is USDA SR Legacy data for "Mung beans, mature seeds, raw" (US samples). Used as an estimate for munggo bought in the Philippines — not measured Philippine data.', true, 'dried mung beans munggo (tuyo) munggo monggo mung beans', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('97067f25-c04b-4c5b-897e-04639b7b8461', 'rice-white-uncooked', 'White rice, uncooked', '{Bigas}', '{bigas,rice,"uncooked rice"}', 'ingredient', 'ph', 'raw', NULL, 365.0, 7.1, 80.0, 0.7, 1.3, 0.1, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169756 "Rice, white, long-grain, regular, raw, unenriched"', true, 'Nutrition per 100 g of uncooked rice is USDA SR Legacy data for "Rice, white, long-grain, regular, raw, unenriched" (US samples). Used as an estimate for Philippine milled rice, which keeps some bran (DA grades rice by bran streak), so real values differ slightly — not measured Philippine data.', true, 'white rice, uncooked bigas bigas rice uncooked rice', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('ab32cba5-1244-4e47-8bb0-3e3f8e0ee939', 'saba-raw', 'Saba banana, raw', '{"Saging saba (hilaw)"}', '{saba,saging,plantain}', 'ingredient', 'ph', 'raw', NULL, 122.0, 1.3, 31.9, 0.4, 2.3, 15.0, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 169130 "Plantains, raw"', true, 'Nutrition per 100 g of peeled fruit is USDA SR Legacy data for "Plantains, raw" (US samples), used as the closest record for saba — not measured Philippine data.', true, 'saba banana, raw saging saba (hilaw) saba saging plantain', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('71c631d2-b156-42a9-a0be-e7cce79f7aa3', 'potato-raw', 'Potato, raw', '{"Patatas (hilaw)"}', '{patatas,potato}', 'ingredient', 'ph', 'raw', NULL, 69.0, 1.7, 15.7, 0.1, 2.4, 1.2, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 170028 "Potatoes, white, flesh and skin, raw"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Potatoes, white, flesh and skin, raw" (US samples). Used as an estimate for potatoes bought in the Philippines — not measured Philippine data.', true, 'potato, raw patatas (hilaw) patatas potato', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('1cd97e06-f2f7-4627-aa4f-11236033034e', 'peanuts-raw', 'Raw peanuts (shelled)', '{"Mani (hilaw)"}', '{mani,peanuts}', 'ingredient', 'ph', 'raw', NULL, 567.0, 25.8, 16.1, 49.2, 8.5, 4.7, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 172430 "Peanuts, all types, raw"', true, 'Nutrition per 100 g of shelled kernels is USDA SR Legacy data for "Peanuts, all types, raw" (US samples). Used as an estimate for peanuts bought in the Philippines — not measured Philippine data.', true, 'raw peanuts (shelled) mani (hilaw) mani peanuts', '2026-09-17 09:17:34.956294+00', '2026-09-17 09:17:34.956294+00', NULL),
	('c704e116-3ea2-4186-8bc3-5fe97e783a34', 'egg-fried', 'Fried egg', '{"Pritong itlog"}', '{itlog,egg,"sunny side up"}', 'generic', 'ph', 'fried', NULL, 196.0, 13.6, 0.8, 14.8, 0.0, 0.4, 'usda_derived', 'USDA FoodData Central SR Legacy (April 2018 release), FDC 173423 "Egg, whole, cooked, fried"', true, 'Nutrition per 100 g is USDA SR Legacy data for "Egg, whole, cooked, fried" (US samples). Used as an estimate for this Philippine food — not measured Philippine data; real values vary with variety, size and preparation.', true, 'fried egg pritong itlog itlog egg sunny side up', '2026-09-17 08:42:48.171398+00', '2026-09-24 07:43:21.66191+00', NULL),
	('a2f9ba94-c3ba-4922-a952-2a6adba1be8e', 'pork', 'Pork', '{sisig,"sisig baboy","pork sisig"}', '{"Filipino sisig","sizzled pork"}', 'prepared_meal', 'ph', 'fried', NULL, 250.0, 16.5, 3.2, 22.8, 0.4, 1.1, 'manual_estimate', 'Estimated from standard cooked pork sisig recipe (FNRI / USDA reference mix)', true, 'Nutrient density varies based on ratio of pork cut fatty tissue, added liver, cooking oil, and mayonnaise.', true, 'pork sisig sisig baboy pork sisig filipino sisig sizzled pork', '2026-09-26 05:47:50.264451+00', '2026-09-26 05:47:50.264451+00', 'Traditional Filipino pork sisig (pork head/belly, liver, onions, chili, seasoning)'),
	('9dd011da-b62a-4bc4-8733-75d81a581798', 'chicken-sisig', 'Chicken sisig', '{"Chicken Sisig","Sisig na Manok"}', '{"Filipino Chicken Sisig"}', 'prepared_meal', 'ph', 'fried', NULL, 210.0, 20.5, 2.8, 12.8, 0.3, 0.9, 'manual_estimate', 'Estimated from standard cooked chicken sisig recipe (FNRI / USDA reference mix)', true, 'Caloric density depends on whether chicken breast or dark meat/skin is used, alongside varying amounts of cooking oil and mayonnaise.', true, 'chicken sisig chicken sisig sisig na manok filipino chicken sisig', '2026-09-26 05:50:56.376064+00', '2026-09-26 05:50:56.376064+00', 'Filipino dish made from minced or chopped chicken meat and liver, seasoned with calamansi, onions, chili peppers, and light mayonnaise or soy sauce.'),
	('8a60b04f-1b13-4d99-bf7b-76285cea0aaf', 'tofu-sisig', 'Tofu sisig', '{"Tofu Sisig","Tokwa''t Sisig","Sisig na Tokwa"}', '{"Vegetarian Sisig","Sizzling Tofu"}', 'prepared_meal', 'ph', 'fried', NULL, 195.0, 11.2, 8.5, 13.4, 1.8, 1.5, 'manual_estimate', 'Estimated from standard pan-fried tofu sisig recipe (USDA firm tofu & sauce reference mix)', true, 'Calorie and fat levels vary based on deep-frying vs. shallow pan-frying, and the proportion of mayonnaise or oil used in the dressing.', true, 'tofu sisig tofu sisig tokwa''t sisig sisig na tokwa vegetarian sisig sizzling tofu', '2026-09-26 05:53:38.100999+00', '2026-09-26 05:53:38.100999+00', 'Filipino dish made from crispy pan-fried or deep-fried tofu cubes tossed with minced onions, chili peppers, calamansi, soy sauce, and mayonnaise.'),
	('f29f02ba-c1ab-40ff-b8bd-ce3f0b96b0a9', 'pork-adobo', 'Pork adobo', '{"Pork Adobo","Adobong Baboy"}', '{"Filipino Pork Adobo"}', 'prepared_meal', 'ph', 'stewed', NULL, 270.0, 17.8, 2.5, 20.8, 0.2, 0.8, 'manual_estimate', 'Estimated from standard cooked pork adobo recipe (FNRI / USDA reference mix)', true, 'Calorie and fat counts vary significantly based on the cut of pork used (pork belly vs. leaner shoulder/pork loin) and how much fat is rendered during simmering.', true, 'pork adobo pork adobo adobong baboy filipino pork adobo', '2026-09-26 05:56:40.810421+00', '2026-09-26 05:56:40.810421+00', 'Traditional Filipino dish made from pork stewed in vinegar, soy sauce, garlic, bay leaves, and black peppercorns until tender.'),
	('800ce78f-0b07-45d9-957d-c5a0ef8155ba', 'chicken-adobo', 'Chicken adobo', '{"Chicken Adobo","Adobong Manok"}', '{"Filipino Chicken Adobo"}', 'prepared_meal', 'ph', 'stewed', NULL, 185.0, 21.2, 2.1, 9.8, 0.2, 0.7, 'manual_estimate', 'Estimated from standard cooked chicken adobo recipe (FNRI / USDA reference mix)', true, 'Nutritional profile varies depending on whether bone-in/skin-on chicken or skinless breast is used, as well as added oil during searing.', true, 'chicken adobo chicken adobo adobong manok filipino chicken adobo', '2026-09-26 05:59:33.692044+00', '2026-09-26 05:59:33.692044+00', 'Traditional Filipino dish made from chicken stewed in soy sauce, vinegar, garlic, bay leaves, and black peppercorns until tender.');


--
-- Data for Name: market_commodities; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."market_commodities" ("id", "slug", "name", "local_names", "commodity_group", "purchase_unit", "grams_per_piece", "grams_per_piece_source", "food_id", "inedible_share", "inedible_share_source", "calculation_note", "sort_order", "active", "created_at") VALUES
	('8abbb65a-1710-4c21-825b-58ad4550f30d', 'egg-white-medium', 'Egg, medium', '{"Itlog, medium"}', 'animal_protein', 'piece', 58.0, 'DA Bantay Presyo specification "56-60 grams/pc" (midpoint; shell included)', '382861da-2cda-477d-9583-fb917dad048a', 0.120, 'USDA SR28 refuse for NDB 01123 "Egg, whole, raw, fresh": 12% (shell)', 'Weight per egg is the midpoint of the DA size range, shell included. Nutrition is USDA raw egg without the shell.', 10, true, '2026-09-17 09:17:34.956294+00'),
	('dd0b2135-ca18-4bf3-aee8-e311259ef9b8', 'egg-white-large', 'Egg, large', '{"Itlog, large"}', 'animal_protein', 'piece', 63.0, 'DA Bantay Presyo specification "61-65 grams/pc" (midpoint; shell included)', '382861da-2cda-477d-9583-fb917dad048a', 0.120, 'USDA SR28 refuse for NDB 01123 "Egg, whole, raw, fresh": 12% (shell)', 'Weight per egg is the midpoint of the DA size range, shell included. Nutrition is USDA raw egg without the shell.', 11, true, '2026-09-17 09:17:34.956294+00'),
	('afef7ee1-cbec-4f78-86eb-fc953202d371', 'chicken-whole-local', 'Whole chicken (dressed)', '{"Manok, buo"}', 'animal_protein', 'kg', NULL, NULL, '5d6facd3-feaa-4e69-921f-4f3fb3e28d53', 0.320, 'USDA SR28 refuse for NDB 05006 "Chicken, broilers or fryers, meat and skin, raw": 32% (bone)', 'DA prices a locally raised, fully dressed whole chicken. USDA''s edible portion is meat and skin, and its waste share is the bone of a US broiler; a Philippine chicken''s bone share may differ.', 20, true, '2026-09-17 09:17:34.956294+00'),
	('0b293272-2395-4961-8c7e-99c9b5b3daf2', 'mung-beans-dried', 'Mung beans (dried)', '{Munggo}', 'plant_protein', 'kg', NULL, NULL, '42c12560-2048-4a85-9b81-0f72ebb1599c', 0.000, 'USDA SR28 refuse for NDB 16080 "Mung beans, mature seeds, raw": 0% (dry seeds as sold)', 'Priced and calculated as dry beans. Cooking adds water, not protein.', 40, true, '2026-09-17 09:17:34.956294+00'),
	('f7950b06-cc68-434e-a705-312befc8af83', 'rice-regular-milled-local', 'Rice, regular milled (local)', '{"Bigas, regular milled"}', 'staple', 'kg', NULL, NULL, '97067f25-c04b-4c5b-897e-04639b7b8461', 0.000, 'USDA SR28 refuse for NDB 20444 "Rice, white, long-grain, regular, raw, unenriched": 0% (milled grain as sold)', 'Priced and calculated as uncooked rice. USDA white rice stands in for regular milled rice (20-40% bran streak).', 60, true, '2026-09-17 09:17:34.956294+00'),
	('415f88bd-ce6f-45e4-98c3-d2b1deb5df90', 'rice-well-milled-local', 'Rice, well milled (local)', '{"Bigas, well milled"}', 'staple', 'kg', NULL, NULL, '97067f25-c04b-4c5b-897e-04639b7b8461', 0.000, 'USDA SR28 refuse for NDB 20444 "Rice, white, long-grain, regular, raw, unenriched": 0% (milled grain as sold)', 'Priced and calculated as uncooked rice. USDA white rice stands in for well milled rice (1-19% bran streak).', 61, true, '2026-09-17 09:17:34.956294+00'),
	('85baef73-13f9-45f3-a05b-d40e19351016', 'banana-saba', 'Saba banana', '{"Saging saba"}', 'staple', 'kg', NULL, NULL, 'ab32cba5-1244-4e47-8bb0-3e3f8e0ee939', 0.350, 'USDA SR28 refuse for NDB 09277 "Plantains, raw": 35% (skin and stems)', 'USDA plantain is the closest record for saba, for both nutrition and peel share.', 62, true, '2026-09-17 09:17:34.956294+00'),
	('9d9540e2-de0d-417d-8c08-42cd852d9785', 'potato-white-local', 'Potato (local)', '{Patatas}', 'staple', 'kg', NULL, NULL, '71c631d2-b156-42a9-a0be-e7cce79f7aa3', 0.250, 'USDA SR28 refuse for NDB 11354 "Potatoes, white, flesh and skin, raw": 25% (parings and trimmings)', 'USDA counts parings and trimmings as waste; if you eat potatoes unpeeled, you waste less.', 63, true, '2026-09-17 09:17:34.956294+00'),
	('04582137-ac43-460e-a4a6-b6ebb46aafd1', 'chicken-breast-fillet', 'Chicken breast fillet (boneless, skinless)', '{"Pitso ng manok, fillet"}', 'animal_protein', 'kg', NULL, NULL, 'af4a3b2e-14cf-4b5b-af44-cec0f76060b5', 0.000, 'USDA SR28 refuse for NDB 05062 "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw": 0%', 'Not in the DA price report — enter the price you pay. Calculated for boneless, skinless fillet only.', 21, true, '2026-09-17 09:17:34.956294+00'),
	('73c39bc3-b965-4d45-8a24-ee55a792d1e0', 'tofu-firm', 'Firm tofu', '{Tokwa}', 'plant_protein', 'kg', NULL, NULL, 'c74edb71-3f07-47f0-9b20-e0a127efdcbd', 0.000, 'USDA SR28 refuse for NDB 16426 "Tofu, raw, firm, prepared with calcium sulfate": 0%', 'Not in the DA price report — enter the price you pay. Tokwa varies in firmness and water, so its protein per kg can differ from USDA firm tofu.', 41, true, '2026-09-17 09:17:34.956294+00'),
	('2aff4802-4ae8-4bc4-9ed2-4bc0b78729cd', 'peanuts-raw-shelled', 'Raw peanuts (shelled)', '{"Mani, hilaw"}', 'plant_protein', 'kg', NULL, NULL, '1cd97e06-f2f7-4627-aa4f-11236033034e', 0.000, 'USDA SR28 refuse for NDB 16087 "Peanuts, all types, raw": 0% (shelled kernels)', 'Not in the DA price report — enter the price you pay. Calculated for shelled kernels only, not peanuts in the shell.', 42, true, '2026-09-17 09:17:34.956294+00'),
	('38f5e595-f7bd-436b-8dc0-2338657a0b68', 'pork-kasim-local', 'Pork shoulder / kasim (local)', '{Kasim}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. The DA report doesn''t say whether kasim is priced with bone, so the share of the bought weight you eat is unknown.', 30, true, '2026-09-17 09:17:34.956294+00'),
	('5bc9d3f0-02ef-428a-bbc4-82912a872f80', 'pork-kasim-imported', 'Pork shoulder / kasim (imported)', '{"Kasim, imported"}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. The DA report doesn''t say whether kasim is priced with bone, so the share of the bought weight you eat is unknown.', 31, true, '2026-09-17 09:17:34.956294+00'),
	('33943af8-a38d-4714-b70b-6c5d55c7650d', 'pork-liempo-local', 'Pork belly / liempo (local)', '{Liempo}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Liempo is usually sold and eaten with the skin, but USDA pork belly treats skin as waste and has no skin-on values.', 32, true, '2026-09-17 09:17:34.956294+00'),
	('da98ecc6-e20f-476c-af4f-b6894e4388d7', 'pork-liempo-imported', 'Pork belly / liempo (imported)', '{"Liempo, imported"}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Liempo is usually sold and eaten with the skin, but USDA pork belly treats skin as waste and has no skin-on values.', 33, true, '2026-09-17 09:17:34.956294+00'),
	('6ae260a9-84e0-4592-82cc-3b472643bba2', 'beef-brisket-local', 'Beef brisket, with bones (local)', '{"Punta y pecho"}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. DA prices brisket with bones; no USDA record gives the bone share of bone-in brisket.', 34, true, '2026-09-17 09:17:34.956294+00'),
	('613d9341-75cb-402c-899f-3d213cca056a', 'tilapia-whole', 'Tilapia (whole)', '{Tilapya}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole-fish prices include head, bones, scales and guts, and there is no checkable edible-yield source yet.', 50, true, '2026-09-17 09:17:34.956294+00'),
	('3cb43a9b-7433-48cb-a6e0-e9a9bc60e5bc', 'bangus-medium-whole', 'Milkfish, medium (whole)', '{Bangus}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole-fish prices include head, bones, scales and guts, and there is no checkable edible-yield source yet.', 51, true, '2026-09-17 09:17:34.956294+00'),
	('284cc4a2-50c5-4aed-b6de-b434cacc4d30', 'galunggong-local-whole', 'Round scad (whole, local)', '{Galunggong}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole-fish prices include head, bones, scales and guts, and there is no checkable edible-yield source yet.', 52, true, '2026-09-17 09:17:34.956294+00'),
	('a316bec5-5538-49d0-8bcf-c5fcea081171', 'alumahan-whole', 'Indian mackerel (whole)', '{Alumahan}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole-fish prices include head, bones, scales and guts, and there is no checkable edible-yield source yet.', 53, true, '2026-09-17 09:17:34.956294+00'),
	('e8ba6efc-362e-4228-86a9-f06db799814c', 'tamban-whole', 'Sardines (whole)', '{Tamban}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole-fish prices include head, bones, scales and guts, and there is no checkable edible-yield source yet.', 54, true, '2026-09-17 09:17:34.956294+00'),
	('b1433618-bfd6-40d9-beb2-576b59550104', 'tambakol-whole', 'Yellowfin tuna (whole, local)', '{Tambakol}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole-fish prices include head, bones, scales and guts, and there is no checkable edible-yield source yet.', 55, true, '2026-09-17 09:17:34.956294+00'),
	('dcca0c6a-2823-49a2-94e6-b733503f1356', 'squid-local', 'Squid (local)', '{Pusit}', 'animal_protein', 'kg', NULL, NULL, NULL, NULL, NULL, 'Price only. Whole squid includes the pen, ink sac and innards, and the USDA squid record gives no waste share for it.', 56, true, '2026-09-17 09:17:34.956294+00');


--
-- Data for Name: commodity_reference_prices; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."commodity_reference_prices" ("id", "commodity_id", "unit", "price_php", "region", "period_start", "period_end", "source", "source_label", "source_reference", "source_item", "specification", "created_at", "note") VALUES
	('2e4e9e94-ffd6-47d2-b611-99e5982ef30b', '8abbb65a-1710-4c21-825b-58ad4550f30d', 'piece', 8.12, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Chicken Egg (White, Medium)', '56-60 grams/pc', '2026-09-17 09:17:34.956294+00', NULL),
	('d98a41ce-2463-4b5b-b5bb-e9619739ec66', 'dd0b2135-ca18-4bf3-aee8-e311259ef9b8', 'piece', 8.73, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Chicken Egg (White, Large)', '61-65 grams/pc', '2026-09-17 09:17:34.956294+00', NULL),
	('c27918fc-5b13-4542-bdbd-ae5425d15d4f', 'afef7ee1-cbec-4f78-86eb-fc953202d371', 'kg', 200.70, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Whole Chicken, Local', 'Fully Dressed', '2026-09-17 09:17:34.956294+00', NULL),
	('2b731484-04ca-4a11-a71c-27950068e574', '0b293272-2395-4961-8c7e-99c9b5b3daf2', 'kg', 149.00, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Mungbean', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('5f45a298-99b7-4414-9186-7e34de173a46', 'f7950b06-cc68-434e-a705-312befc8af83', 'kg', 44.72, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Local Commercial Rice, Regular Milled', '20-40% bran streak', '2026-09-17 09:17:34.956294+00', NULL),
	('f71095ee-4af5-4598-b2a0-8546c8d26380', '415f88bd-ce6f-45e4-98c3-d2b1deb5df90', 'kg', 48.78, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Local Commercial Rice, Well Milled', '1-19% bran streak', '2026-09-17 09:17:34.956294+00', NULL),
	('b462f9ec-0ffd-4fc9-a9cd-bfa8aa5792e8', '85baef73-13f9-45f3-a05b-d40e19351016', 'kg', 64.10, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Banana (Saba)', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('7b2bc747-0225-41fc-a5e7-b2a1f01bf4cb', '9d9540e2-de0d-417d-8c08-42cd852d9785', 'kg', 155.20, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'White Potato, Local', '10-12 pcs/kg', '2026-09-17 09:17:34.956294+00', NULL),
	('400029dc-478c-49ae-bcc5-6581d632fa56', '38f5e595-f7bd-436b-8dc0-2338657a0b68', 'kg', 323.66, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Pork Picnic Shoulder (Kasim), Local', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('9128ed1d-c475-47b3-a3f4-f3b8817ff8ad', '5bc9d3f0-02ef-428a-bbc4-82912a872f80', 'kg', 240.80, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Pork Picnic Shoulder (Kasim), Imported', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('932d7361-575b-47b2-8699-e6fc65d46e87', '33943af8-a38d-4714-b70b-6c5d55c7650d', 'kg', 377.74, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Pork Belly (Liempo), Local', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('98194288-5ba8-428b-9e6f-ae76df9e42f5', 'da98ecc6-e20f-476c-af4f-b6894e4388d7', 'kg', 306.36, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Pork Belly (Liempo), Imported', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('8b5afbea-5996-47ff-a61a-7f7ac1591923', '6ae260a9-84e0-4592-82cc-3b472643bba2', 'kg', 441.22, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Beef Brisket, Local', 'Meat with Bones', '2026-09-17 09:17:34.956294+00', NULL),
	('ce1f273d-bbc2-4d40-8161-8b9f0f10843d', '613d9341-75cb-402c-899f-3d213cca056a', 'kg', 158.35, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Tilapia', 'Medium (5-6 pcs/kg)', '2026-09-17 09:17:34.956294+00', NULL),
	('b6b24036-4f57-48ca-9e3c-994e6c203114', '3cb43a9b-7433-48cb-a6e0-e9a9bc60e5bc', 'kg', 244.95, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Bangus, Medium', 'Medium (3-4 pcs/kg)', '2026-09-17 09:17:34.956294+00', NULL),
	('a59f7fc2-9e42-41e1-b339-a82676671826', '284cc4a2-50c5-4aed-b6de-b434cacc4d30', 'kg', 310.79, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Galunggong, Local', 'Male, Medium (12-14 pcs/kg)', '2026-09-17 09:17:34.956294+00', NULL),
	('001faa85-190b-43f2-a6c6-47c1ee1d5216', 'a316bec5-5538-49d0-8bcf-c5fcea081171', 'kg', 353.67, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Alumahan (Indian Mackerel)', 'Medium (4-6 pcs/kg)', '2026-09-17 09:17:34.956294+00', NULL),
	('b6193377-8dd2-4dd0-b84f-623d037b28ed', 'e8ba6efc-362e-4228-86a9-f06db799814c', 'kg', 153.24, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Sardines (Tamban)', NULL, '2026-09-17 09:17:34.956294+00', NULL),
	('5e311a53-5edd-4ed0-9541-db23398ed9b8', 'b1433618-bfd6-40d9-beb2-576b59550104', 'kg', 312.57, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Tambakol (Yellow-Fin Tuna), Local', 'Medium, Fresh or Chilled', '2026-09-17 09:17:34.956294+00', NULL),
	('a0848b5f-3cfc-43cb-93d2-b669bd45eb6f', 'dcca0c6a-2823-49a2-94e6-b733503f1356', 'kg', 472.54, 'NCR', '2026-09-07', '2026-09-13', 'da_bantay_presyo', 'DA Bantay Presyo — Weekly Average Retail Price of Selected Agri-Fishery Commodities in NCR Markets (DA-AMAS)', 'https://www.da.gov.ph/wp-content/uploads/2026/09/Weekly-Average-Prices-September-7-13-2026.pdf', 'Squid (Pusit Bisaya), Local', 'Medium', '2026-09-17 09:17:34.956294+00', NULL);


--
-- Data for Name: exercises; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."exercises" ("id", "name", "display_name", "created_at", "primary_attribute", "metric_type") VALUES
	('d6c7c159-0a44-4cff-af75-7cc2757333c9', 'pushup', 'Push Up', '2026-07-01 06:06:28.831285+00', 'strength', 'reps'),
	('adce978e-2d73-4b08-9eb6-7a1c8bd7aa5d', 'pullup', 'Pull Up', '2026-07-01 06:06:28.831285+00', 'strength', 'reps'),
	('3ee9cb82-b2c3-4a73-a8fc-e4557c3e9143', 'squat', 'Squat', '2026-07-01 06:06:28.831285+00', 'strength', 'reps'),
	('93088073-fd9d-4929-8c00-e1e5ca3f961f', 'deadlift', 'Deadlift', '2026-07-01 06:06:28.831285+00', 'strength', 'reps'),
	('1224acdd-db2f-41a2-a5a5-40038a94c896', 'benchpress', 'Bench Press', '2026-07-01 06:06:28.831285+00', 'strength', 'reps'),
	('329b433c-b5e6-41e3-b1aa-904a6aea552b', 'barbellbicepscurl', 'Barbell Bicep Curl', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('df5a3247-961c-4ea5-be66-4bb305bc177b', 'declinebenchpress', 'Decline Bench Press', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('98451c63-c7e7-454d-ab40-64280e2ebffc', 'hammercurl', 'Hammer Curl', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('7ac18628-e04a-4534-9c8f-ea6b21f9b0c0', 'hipthrust', 'Hip Thrust', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('3380b188-1690-46a8-8e96-1fb22cf018a6', 'inclinebenchpress', 'Incline Bench Press', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('c0f0285c-88e9-4e8a-8b5e-cef91495f56d', 'latpulldown', 'Lat Pulldown', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('05368ffc-f32c-491b-a152-011e6a671f7e', 'romaniandeadlift', 'Romanian Deadlift', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('b9803b5e-b50f-4086-8ed8-403694d1f20b', 'shoulderpress', 'Shoulder Press', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('4e3baebb-a1ef-41e0-a0c9-0dffd3c68875', 'tbarrow', 'T-Bar Row', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('35603fdb-9f19-4f68-a141-22ad4eb90ce2', 'tricepdips', 'Tricep Dips', '2026-09-02 22:56:14.11964+00', 'strength', 'reps'),
	('ce1fb621-6d30-48f2-b9b4-84219846b97a', 'burpee', 'Burpee', '2026-07-01 06:06:28.831285+00', 'agility', 'reps'),
	('422d1b97-0edf-42ec-bed7-db5a5b8b6efb', 'lunges', 'Lunges', '2026-07-01 06:06:28.831285+00', 'agility', 'reps'),
	('4f4291b9-379e-49b3-b9cf-5f863ed07265', 'legraises', 'Leg Raises', '2026-09-02 22:56:14.11964+00', 'agility', 'reps'),
	('917b2910-bba7-4292-b424-f1d473e2c6ca', 'russiantwist', 'Russian Twist', '2026-09-02 22:56:14.11964+00', 'agility', 'reps'),
	('1f36ae08-4ad5-4e2e-a81f-569aced321b1', 'chestflymachine', 'Chest Fly Machine', '2026-09-02 22:56:14.11964+00', 'vitality', 'reps'),
	('1191f551-dbc6-48c5-91f2-e52a8390bbbf', 'lateralraise', 'Lateral Raise', '2026-09-02 22:56:14.11964+00', 'vitality', 'reps'),
	('ee1f3f64-d102-4383-b49b-c7fa09a81a66', 'legextension', 'Leg Extension', '2026-09-02 22:56:14.11964+00', 'vitality', 'reps'),
	('6a91c663-c8a9-4a97-9a4f-91a08c735d81', 'triceppushdown', 'Tricep Pushdown', '2026-09-02 22:56:14.11964+00', 'vitality', 'reps'),
	('40121bd6-4482-489d-b352-70b778e6c76f', 'jumpingjacks', 'Jumping Jacks', '2026-09-04 05:33:22.279542+00', 'agility', 'reps'),
	('670de909-f524-4f2b-9fd6-1d525108b094', 'jogging', 'Jogging', '2026-09-04 05:33:22.279542+00', 'vitality', 'distance'),
	('7b053d77-42cd-46a4-829c-747642976799', 'walking', 'Walking', '2026-09-04 05:33:22.279542+00', 'vitality', 'distance'),
	('fb043efe-6afd-4d82-b7a2-056cab245425', 'cycling', 'Cycling', '2026-09-04 05:33:22.279542+00', 'vitality', 'duration'),
	('6727c48f-bce4-4f89-8842-7f4c1cea33b7', 'plank', 'Plank', '2026-07-01 06:06:28.831285+00', 'vitality', 'duration'),
	('1a9e8eb9-dbfd-47cb-befa-57322cd43e59', 'shadowboxing', 'Shadow Boxing', '2026-09-05 01:22:15.72857+00', 'agility', 'duration'),
	('881f503c-6b8e-4bc5-8dce-7053c1eb6a5c', 'mountainclimbers', 'Mountain Climbers', '2026-09-05 01:22:15.72857+00', 'agility', 'reps'),
	('bd300f6f-30b8-40a8-a81a-7cc5c7e0f1df', 'snatch', 'Snatch', '2026-09-10 06:47:49.274586+00', 'strength', 'reps'),
	('48bada87-8ce7-4a37-bfea-e15b3450b22d', 'cleanandjerk', 'Clean & Jerk', '2026-09-10 06:47:49.274586+00', 'strength', 'reps'),
	('99bfdac4-32b3-467b-a912-728224cf58c1', 'powerclean', 'Power Clean', '2026-09-10 06:47:49.274586+00', 'strength', 'reps'),
	('d3dfd178-92fc-49ae-9a84-4e146053942a', 'farmerscarry', 'Farmer''s Carry', '2026-09-10 06:47:49.274586+00', 'strength', 'reps'),
	('844321c9-a7b4-4f51-abad-b7c1f585aef2', 'yokewalk', 'Yoke Walk', '2026-09-10 06:47:49.274586+00', 'strength', 'reps'),
	('ac85c3ab-2747-4157-96c8-3c8bd7c62b2c', 'atlasstone', 'Atlas Stone', '2026-09-10 06:47:49.274586+00', 'strength', 'reps'),
	('07682c2b-0930-4e27-ae1a-76c2eab226e2', 'rucking', 'Rucking', '2026-09-10 06:47:49.274586+00', 'vitality', 'distance'),
	('488bf92c-1501-45c9-a6bf-88e2156027f9', 'sideplank', 'Side Plank', '2026-09-14 00:58:09.369897+00', 'vitality', 'duration'),
	('3c24dc44-dbfe-42f6-aca2-38c1fdc6697f', 'wallsit', 'Wall Sit', '2026-09-14 00:58:09.369897+00', 'strength', 'duration'),
	('9fc6ff38-b6ce-40e5-99c0-bf20e5e1492f', 'bulgariansplitsquat', 'Bulgarian Split Squat', '2026-09-17 04:38:30.393541+00', 'strength', 'reps');


--
-- Data for Name: food_servings; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."food_servings" ("id", "food_id", "label", "grams", "is_estimate", "sort_order") VALUES
	('0d9e301f-841b-440f-94a5-7447eaf68320', '1501d314-f8c5-442f-99dd-f77bedd1d7ee', '1 large egg', 50.0, true, 0),
	('fad827b1-3ddc-4194-a3ae-c342c12463bc', '114cfa66-bd83-4a15-9724-41efcd8d8117', '1 cup (tasa)', 158.0, true, 0),
	('0dd0ca4c-0f38-4b60-ad69-8a21da14f17b', 'f5f921ae-950f-4221-99f2-6792af139895', '1 cup (tasa)', 165.0, true, 0),
	('e5524374-12de-4f6b-9768-88fff76d257a', 'ba1aa323-69e2-4c0f-8322-c7e0d08c6cb1', '1 bowl (mangkok)', 250.0, true, 0),
	('bdd117b0-580c-4c20-9eb9-183f596692b5', '77cbe759-e2ea-47d7-9162-25308a97e799', '1 piece (medium)', 35.0, true, 0),
	('eb0277f4-9721-4f85-92e3-4a38208045ce', '0ae8a0ec-8a5f-4397-9904-38ff64f0c49b', '1 slice', 29.0, true, 0),
	('f5855dbb-f476-438a-b6bc-def8fb95d064', '6d1eacd3-9624-4c9d-af65-de67dbfcefc3', '1 cup', 89.0, true, 0),
	('050aea42-8a2f-4e63-95ae-87ee23bfeb53', 'de407ef7-d4c7-422f-959b-ad8a57bb7668', '1 can (drained)', 165.0, true, 0),
	('8d9c94fe-4766-4047-91ee-db1f21ce34e3', 'f39dfb88-a3bb-45e2-9d4e-cfef1235d763', '1 cup (tasa)', 202.0, true, 0),
	('8fbf4f1b-601d-4eba-9e12-227c91c95271', '586cc9b3-a030-4684-8cf7-2e4014520c64', '1 cup (tasa)', 98.0, true, 0),
	('9f4e3b8f-8f86-41d5-87d9-7f879e6ca066', '80a2f6dd-215c-4144-b400-347089898d34', '1 cup (tasa)', 170.0, true, 0),
	('bd2f8f04-60d0-47cc-a8e2-c9f1a12cc599', 'b69ab694-9002-4fa8-aaa6-3cbac8f7ba0c', '1 cup (tasa)', 104.0, true, 0),
	('c11a913e-f60a-499a-abf1-76551ae398f7', '954f214f-3a8d-47fc-bd1c-459fa98d358c', '1 cup (tasa)', 245.0, true, 0),
	('98169fc3-c02a-40fa-af32-4dbfb0257bb9', 'db350d9d-01b8-41e5-bc31-d43daf5eee4f', '1 cup (tasa)', 99.0, true, 0),
	('de568508-adfe-4369-9720-9704e8fb50b3', 'f6e218d1-86ed-4f84-bc58-bc2e8e36e777', '1 medium', 151.0, true, 0),
	('bc19f717-c647-4396-965e-526e8917a15f', 'a93c1ec1-5b4a-4530-bcce-37fc33d04494', '1 piece', 80.0, true, 0),
	('1d1d6fc1-5068-4b9a-b132-397ca26b9fc3', 'e8fe75b1-c8e6-4168-86e0-dd0698dff2c1', '1 medium', 118.0, true, 0),
	('291e72e3-1cbd-47ad-97a9-a0bbee1c4d2a', '884014ad-5332-444a-9289-736ddc74a1dc', '1 cup, sliced', 165.0, true, 0),
	('59cc55fc-0ccb-4b85-acb0-43b0f534a412', '72d1adb0-e8e1-418a-85f7-1ffe1c178e7a', '1 cup, cubed', 145.0, true, 0),
	('fa4ae84b-0fc1-4e64-ab01-1ffb548602a9', '6b8105dd-e0c5-4780-8fd7-080484632c74', '1 cup, chunks', 165.0, true, 0),
	('584525ac-9411-4938-90ef-90d3a9d663ed', 'be40521e-a893-42ac-9981-a154ea37ca22', '1 oz (about 28 pieces)', 28.4, true, 0),
	('008a4bf5-ab12-4128-8db2-acca3aa131de', '916c00c7-68f0-4ff6-9435-90d5430ede75', '1 cup (tasa)', 240.0, true, 0),
	('e1763d49-95a9-4a0a-8023-b7b3990b1516', '56c6804c-10c9-4dd5-81dd-77d0d5f9c42f', '1 cup (tasa)', 244.0, true, 0),
	('9aba4118-ce32-4040-95a2-03a08120c916', 'f229f4f2-a4d5-4f97-bb83-cea1e103fcfc', '1 cup (tasa)', 234.0, true, 0),
	('7cc926c8-6b0e-4976-bcfc-2121f898dbe1', 'c704e116-3ea2-4186-8bc3-5fe97e783a34', '1 large egg', 46.0, true, 1),
	('93f2d111-014d-4860-a41f-d08f72f826e0', 'a2f9ba94-c3ba-4922-a952-2a6adba1be8e', '1 cup', 150.0, true, 1),
	('bc595ca0-7f26-4843-9d96-c1f9459989ba', '9dd011da-b62a-4bc4-8733-75d81a581798', '1 cup', 140.0, true, 1),
	('83ac5431-6f69-4614-920b-5e235d9eb1a0', '8a60b04f-1b13-4d99-bf7b-76285cea0aaf', '1 cup', 140.0, true, 1),
	('a588d086-fad7-4961-bee9-afd82ba97be7', 'f29f02ba-c1ab-40ff-b8bd-ce3f0b96b0a9', '1 cup', 160.0, true, 1),
	('69711a23-8d1b-4e7e-bcd5-3ca66c632137', '800ce78f-0b07-45d9-957d-c5a0ef8155ba', '1 cup', 150.0, true, 1);


--
-- Data for Name: game_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."game_config" ("key", "value", "description", "updated_at") VALUES
	('form_damage', '{"quality_floor": 0.5, "crit_threshold": 0.95, "max_multiplier": 1.5, "min_multiplier": 1.0, "crit_multiplier": 1.5}', 'Form score to damage. min_multiplier is 1.0 on purpose: completing an objective must always be enough to clear a boss whose HP was validated against the objective damage, so poor form slows a fight and costs crits but can never make a finished objective worthless.', '2026-09-11 09:58:49.221319+00'),
	('mission_rules', '{"retry_allowed": true, "pause_max_seconds": 300, "replay_grants_rewards": false, "objective_grace_seconds": 15}', 'Mission attempt rules. objective_grace_seconds covers repositioning the phone between a side-view and a front-view exercise. replay_grants_rewards stays false: the first clear is the paying clear, though a replay still logs the workout itself.', '2026-09-11 09:58:49.221319+00'),
	('combat_defaults', '{"player_hp": 100}', 'Standardised starting combat HP. Deliberately NOT derived from level or attributes, so a high-level player still feels a Dungeon. This is an RPG statistic and has nothing to do with real-world health.', '2026-09-11 09:58:49.221319+00'),
	('streak_rules', '{"timezone": "Asia/Manila", "restore_max_age_days": 3}', 'The streak day boundary. One fixed zone, not the device clock: a device in another zone would otherwise compute a different streak from the server.', '2026-09-11 09:58:49.221319+00'),
	('plausibility', '{"min_seconds_per_rep": {"squat": 0.9, "lunges": 1.0, "pullup": 1.0, "pushup": 0.7, "deadlift": 1.2, "hipthrust": 0.9, "legraises": 0.9, "jumpingjacks": 0.4, "lateralraise": 0.8, "shoulderpress": 0.9, "mountainclimbers": 0.35, "romaniandeadlift": 1.2, "barbellbicepscurl": 0.8}, "duration_tolerance_seconds": 5, "default_min_seconds_per_rep": 0.8}', 'Server-side sanity limits on submitted results. The camera runs on the player device, so a result is a claim: these bounds reject claims no human body could produce (30 push-ups in four seconds) even though they cannot prove an honest one.', '2026-09-11 09:58:49.221319+00'),
	('mission_grades', '{"A": 0.85, "B": 0.70, "S": 0.95}', 'Average form quality needed for each clear grade; anything below B is a C.', '2026-09-11 14:15:20.685903+00'),
	('dungeon_objectives', '{"fallback": ["squat", "pushup", "plank", "lunges", "jumpingjacks", "mountainclimbers"], "avoid_last": 2, "base_damage": {"easy": 60, "hard": 150, "medium": 100}, "reps_target": {"easy": 15, "hard": 35, "medium": 25}, "duration_target": {"easy": 30, "hard": 90, "medium": 60}, "objective_seconds": {"easy": 300, "hard": 420, "medium": 360}}', 'How a Dungeon objective is built. The pool is the player''s specialization exercises that a camera can watch; fallback fills in when that is too thin (lifestyle has none). avoid_last stops the same movement being handed out twice in a row.', '2026-09-11 23:31:29.459862+00'),
	('dungeon_consolation', '{"tiers": [{"xp": 0, "gold": 10, "min_percent": 0}, {"xp": 100, "gold": 30, "min_percent": 25}, {"xp": 250, "gold": 60, "min_percent": 60}]}', 'Paid when an ADMIN cancels a running Dungeon, by how far the party had got. A normal failure pays nothing — cancellation is our fault, not the player''s.', '2026-09-11 23:31:29.459862+00'),
	('dungeon_team_penalty', '{"easy": 5, "hard": 25, "medium": 12, "teammate_share": 0.5}', 'Combat HP every active party member loses when one objective fails, by objective difficulty.', '2026-09-12 10:42:22.842805+00'),
	('dungeon_rules', '{"party_max": 4, "solo_warning_ranks": ["SSS", "unknown", "x"], "state_poll_seconds": 3, "revive_window_seconds": 120, "disconnect_grace_seconds": 120, "min_contribution_percent": 10, "heartbeat_interval_seconds": 15, "party_join_requires_friend": true}', 'Dungeon battle rules. party_max is 4 because the no-duplicate-exercise rule draws from a 15-exercise camera pool that narrows hard once a specialization filter is applied.', '2026-09-12 10:42:22.842805+00'),
	('dungeon_rewards', '{"no_pool_ok": true, "duplicate_gold_ratio": 0.5}', 'Reward-roll rules. duplicate_gold_ratio is the share of a collectible''s gold_value paid when a player already owns it and the pool has no unowned alternative left.', '2026-09-12 15:32:49.080569+00'),
	('camera_trackable', '["squat", "pushup", "lunges", "barbellbicepscurl", "legraises", "jumpingjacks", "lateralraise", "hipthrust", "shoulderpress", "deadlift", "romaniandeadlift", "pullup", "mountainclimbers", "plank", "shadowboxing", "tricepdips", "sideplank", "wallsit", "latpulldown", "bulgariansplitsquat"]', 'Camera exercises AUTHORISED to produce rewards: camera XP, form-verified strength records, and Mission/Dungeon objectives. Necessary but not sufficient — the lifecycle must also be validated/production and an explicit camera xp_config row must exist (public.camera_reward_eligible). May be narrower than the validated set, never wider.', '2026-09-18 05:14:25.703406+00'),
	('camera_exercise_lifecycle', '{"plank": "production", "squat": "production", "lunges": "production", "pullup": "production", "pushup": "production", "wallsit": "validated", "deadlift": "production", "hipthrust": "production", "legraises": "production", "sideplank": "validated", "tricepdips": "validated", "latpulldown": "validated", "jumpingjacks": "production", "lateralraise": "production", "shadowboxing": "production", "shoulderpress": "production", "mountainclimbers": "production", "romaniandeadlift": "production", "barbellbicepscurl": "production", "bulgariansplitsquat": "validated"}', 'Validation stage of each camera tracker, by logging name: draft, implemented, tested, validated or production. Says whether the tracker WORKS; it does not authorise rewards on its own (see camera_trackable). Must equal the client registry; src/lib/dungeons.test.js enforces it.', '2026-09-18 05:14:25.703406+00');


--
-- Data for Name: mission_chapters; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."mission_chapters" ("id", "number", "name", "is_active", "created_at") VALUES
	('3058899f-0b5d-401c-b16e-39ae40e054e7', 1, 'The Awakening', true, '2026-09-11 14:15:20.685903+00');


--
-- Data for Name: missions; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."missions" ("id", "chapter_id", "level_number", "name", "boss_id", "rank", "max_hp", "time_limit_seconds", "difficulty", "is_boss_level", "reward_xp", "reward_gold", "reward_collectible_id", "is_active", "created_at") VALUES
	('55b62509-0ded-4a0c-aa77-375d6e579f77', '3058899f-0b5d-401c-b16e-39ae40e054e7', 1, 'Gate of Rust', '0d507c24-2aff-4058-90d4-569f008e9305', 'E', 100, 900, 'easy', false, 150, 15, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('41d3c7ae-d8a3-4aa2-a793-4cb17d9e2d15', '3058899f-0b5d-401c-b16e-39ae40e054e7', 2, 'The Slick Hollow', 'bf6a5c26-63ab-4a5b-9237-dfc462c27c86', 'E', 180, 1080, 'easy', false, 200, 20, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('ff5af35e-87b7-4edc-ac6a-07b9ba0e8a6f', '3058899f-0b5d-401c-b16e-39ae40e054e7', 3, 'Hound in the Tunnels', '42794266-0162-4341-ab69-4bb4702ef967', 'D', 200, 1200, 'easy', false, 260, 25, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('4290672e-ce7e-47de-8a79-f9a273782e08', '3058899f-0b5d-401c-b16e-39ae40e054e7', 4, 'Ashfall Corridor', 'af593e96-fc24-40b7-8c77-98ff886871c4', 'D', 240, 1200, 'medium', false, 320, 30, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('1968d611-c5e5-444a-9f33-25c241cfa246', '3058899f-0b5d-401c-b16e-39ae40e054e7', 5, 'The Sentinel Stair', '9a0b5530-3e9f-49b6-ab00-975f477e464f', 'C', 270, 1500, 'medium', false, 400, 40, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('40bb600b-715a-4350-b271-88f66bd6162b', '3058899f-0b5d-401c-b16e-39ae40e054e7', 6, 'Reaver of the Dry Sea', 'c389fbc4-c8e5-48d9-8992-b33e6d8fe120', 'C', 300, 1500, 'medium', false, 480, 45, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('da1a62d3-4819-4576-821b-7ecc395541b5', '3058899f-0b5d-401c-b16e-39ae40e054e7', 7, 'Revenant Under Ice', '67735ee6-9bac-4833-ba20-d55e2dbadc38', 'B', 340, 1800, 'medium', false, 580, 55, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('3972d65e-e20d-4e77-a0b2-a8cc2160f9aa', '3058899f-0b5d-401c-b16e-39ae40e054e7', 8, 'Warden of the Red Gate', 'c8e69931-d75e-4aee-9f18-a6838ad15d83', 'B', 370, 1800, 'hard', false, 700, 65, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('fddf2682-efa1-4eea-a52a-361d58ad76ba', '3058899f-0b5d-401c-b16e-39ae40e054e7', 9, 'Stalker in the Void', '4d609640-a3dc-4482-8d59-b42ec3a9b856', 'A', 410, 2100, 'hard', false, 850, 80, NULL, true, '2026-09-11 14:15:20.685903+00'),
	('4b021366-8bad-438a-bd61-cbdad73ee5b3', '3058899f-0b5d-401c-b16e-39ae40e054e7', 10, 'Throne of the Abyss', '99f2c619-df03-4c24-8244-75fd9efb3910', 'S', 620, 2700, 'hard', true, 1200, 120, NULL, true, '2026-09-11 14:15:20.685903+00');


--
-- Data for Name: mission_objectives; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."mission_objectives" ("id", "mission_id", "sequence", "exercise", "target_value", "objective_time_limit_seconds", "base_damage") VALUES
	('13c7d113-1e0f-4b68-b8de-ebad30ce3f80', '55b62509-0ded-4a0c-aa77-375d6e579f77', 1, 'pushup', 15, NULL, 50),
	('8573d5da-7a35-4e2c-8e77-e6c5012652b5', '55b62509-0ded-4a0c-aa77-375d6e579f77', 2, 'squat', 20, NULL, 50),
	('5fe377d3-fde2-4ca9-9820-6868cf409aff', '41d3c7ae-d8a3-4aa2-a793-4cb17d9e2d15', 1, 'pushup', 20, NULL, 60),
	('2aeb3078-9fa1-49d2-ab37-aa64796d76f6', '41d3c7ae-d8a3-4aa2-a793-4cb17d9e2d15', 2, 'squat', 25, NULL, 60),
	('0a6f6b1c-cb9d-4b5d-ace2-7997ae93f2d8', '41d3c7ae-d8a3-4aa2-a793-4cb17d9e2d15', 3, 'plank', 45, NULL, 60),
	('422a542e-827d-4b57-9ece-df9ccd2fbdd1', 'ff5af35e-87b7-4edc-ac6a-07b9ba0e8a6f', 1, 'lunges', 20, NULL, 70),
	('7ad417e3-7800-4d72-89b1-4e8eba07f665', 'ff5af35e-87b7-4edc-ac6a-07b9ba0e8a6f', 2, 'jumpingjacks', 40, NULL, 70),
	('ce1f8be0-efa3-4fe5-b7e3-bbd4389451f9', 'ff5af35e-87b7-4edc-ac6a-07b9ba0e8a6f', 3, 'pushup', 20, NULL, 60),
	('bac52ee5-fc9e-4441-a590-6933735d9e3d', '4290672e-ce7e-47de-8a79-f9a273782e08', 1, 'mountainclimbers', 40, NULL, 80),
	('0361c74a-4abb-4779-840f-add1cdec4815', '4290672e-ce7e-47de-8a79-f9a273782e08', 2, 'plank', 60, NULL, 80),
	('e37dc0c9-cc87-40e1-bda2-02ed5dbc9a78', '4290672e-ce7e-47de-8a79-f9a273782e08', 3, 'squat', 30, NULL, 80),
	('56850895-f217-4992-a7bc-3b7144862b96', '1968d611-c5e5-444a-9f33-25c241cfa246', 1, 'squat', 35, NULL, 90),
	('5abb0589-ddcf-4693-a60e-013bb1dae544', '1968d611-c5e5-444a-9f33-25c241cfa246', 2, 'pushup', 25, NULL, 90),
	('0f8423af-f1f8-4157-a1fd-e4aeca0811e2', '1968d611-c5e5-444a-9f33-25c241cfa246', 3, 'lunges', 24, NULL, 90),
	('c02bc965-b822-40a0-8853-5612ce82bc36', '40bb600b-715a-4350-b271-88f66bd6162b', 1, 'shadowboxing', 90, NULL, 100),
	('0d901d84-5d98-43cb-981b-66ebd65d4791', '40bb600b-715a-4350-b271-88f66bd6162b', 2, 'jumpingjacks', 50, NULL, 100),
	('3992ee64-01ec-473a-af7f-7b8b75126ea8', '40bb600b-715a-4350-b271-88f66bd6162b', 3, 'legraises', 25, NULL, 100),
	('3f790caa-c5e0-47e9-bf6a-4a195b49b62e', 'da1a62d3-4819-4576-821b-7ecc395541b5', 1, 'pullup', 8, NULL, 120),
	('fe70c2a5-9442-4f38-8857-ddfd42737ff1', 'da1a62d3-4819-4576-821b-7ecc395541b5', 2, 'pushup', 30, NULL, 110),
	('2c3d950e-5796-4f31-9537-220b7558e40b', 'da1a62d3-4819-4576-821b-7ecc395541b5', 3, 'plank', 75, NULL, 110),
	('a17608a7-6de9-45a9-9b6d-aff1b9d02e05', '3972d65e-e20d-4e77-a0b2-a8cc2160f9aa', 1, 'squat', 40, NULL, 130),
	('500e24b0-9aae-4c83-8096-85a568d9a065', '3972d65e-e20d-4e77-a0b2-a8cc2160f9aa', 2, 'lunges', 30, NULL, 120),
	('036608f7-3bbb-45cb-8bdb-d209fe1e6759', '3972d65e-e20d-4e77-a0b2-a8cc2160f9aa', 3, 'mountainclimbers', 50, NULL, 120),
	('698eedfc-09e7-4560-85ff-31052978ce3c', 'fddf2682-efa1-4eea-a52a-361d58ad76ba', 1, 'pullup', 10, NULL, 150),
	('6f0dde90-77f1-4801-866b-aaf1da838ba0', 'fddf2682-efa1-4eea-a52a-361d58ad76ba', 2, 'shoulderpress', 20, NULL, 130),
	('31253853-535c-4df9-872e-9785741c74ef', 'fddf2682-efa1-4eea-a52a-361d58ad76ba', 3, 'plank', 90, NULL, 130),
	('8055855f-65b2-4f78-8754-ae18b146c9ce', '4b021366-8bad-438a-bd61-cbdad73ee5b3', 1, 'pushup', 40, NULL, 160),
	('80978b12-0606-4ca3-8256-883e449e7be8', '4b021366-8bad-438a-bd61-cbdad73ee5b3', 2, 'squat', 50, NULL, 160),
	('3c856018-f0fe-42c5-9540-c1ae31ee43c5', '4b021366-8bad-438a-bd61-cbdad73ee5b3', 3, 'lunges', 40, NULL, 150),
	('511b4233-f5c6-4a30-881d-16818ae1b813', '4b021366-8bad-438a-bd61-cbdad73ee5b3', 4, 'shadowboxing', 120, NULL, 150);


--
-- Data for Name: privacy_export_coverage; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."privacy_export_coverage" ("table_name", "column_name", "status", "reason") VALUES
	('users', 'id', 'exported', 'Profile, including body information you entered.'),
	('workout_logs', 'user_id', 'exported', 'Workout history.'),
	('strength_records', 'user_id', 'exported', 'Strength records.'),
	('rank_history', 'user_id', 'exported', 'Rank changes.'),
	('xp_grants', 'user_id', 'exported', 'XP awards.'),
	('user_specialization_xp', 'user_id', 'exported', 'XP per path.'),
	('fitrack_logs', 'user_id', 'exported', 'Meal logs and their nutrition snapshots.'),
	('ai_suggestions', 'user_id', 'exported', 'AI suggestions generated for you.'),
	('user_exercise_templates', 'user_id', 'exported', 'Saved reference reps (joint coordinates).'),
	('routines', 'user_id', 'exported', 'Routines, with their exercises.'),
	('chat_messages', 'user_id', 'exported', 'Global chat messages you sent.'),
	('direct_messages', 'sender_id', 'exported', 'Direct messages you sent.'),
	('direct_messages', 'recipient_id', 'exported', 'Direct messages you received.'),
	('friendships', 'requester_id', 'exported', 'Friend requests you sent.'),
	('friendships', 'addressee_id', 'exported', 'Friend requests you received.'),
	('gymmunity_posts', 'user_id', 'exported', 'Community posts.'),
	('user_reports', 'reporter_id', 'exported', 'Reports you filed (without the reviewing moderator).'),
	('user_reports', 'reported_user_id', 'excluded', 'Reports filed ABOUT you would identify the reporter. Pending privacy review.'),
	('user_reports', 'reviewed_by', 'excluded', 'Moderator review records. Pending privacy review.'),
	('bug_reports', 'user_id', 'exported', 'Bug reports you filed (without the reviewing moderator).'),
	('bug_reports', 'reviewed_by', 'excluded', 'Moderator review records. Pending privacy review.'),
	('gold_ledger', 'user_id', 'exported', 'Gold history.'),
	('shop_purchases', 'user_id', 'exported', 'Shop purchases.'),
	('user_inventory', 'user_id', 'exported', 'Inventory.'),
	('item_uses', 'user_id', 'exported', 'Item uses.'),
	('user_collectibles', 'user_id', 'exported', 'Collectibles.'),
	('streak_shields', 'user_id', 'exported', 'Streak shields.'),
	('mission_attempts', 'user_id', 'exported', 'Mission attempts, with objective results.'),
	('mission_clears', 'user_id', 'exported', 'Mission clears.'),
	('dungeon_runs', 'user_id', 'exported', 'Dungeon runs, with objective results.'),
	('dungeon_clears', 'user_id', 'exported', 'Dungeon clears.'),
	('dungeon_event_invites', 'user_id', 'exported', 'Dungeon invites you received (without who sent them).'),
	('dungeon_event_invites', 'invited_by', 'excluded', 'Admin record of who sent an invite.'),
	('dungeon_events', 'created_by', 'excluded', 'Admin game configuration, not personal activity.'),
	('dungeon_battles', 'leader_id', 'excluded', 'Shared battle state; your participation is exported through dungeon_runs.'),
	('user_budget_settings', 'user_id', 'exported', 'Daily food budget.'),
	('user_commodity_prices', 'user_id', 'exported', 'Prices you entered.'),
	('user_consents', 'user_id', 'exported', 'Notices you acknowledged and choices you made.'),
	('verification_applications', 'user_id', 'exported', 'Coach applications and their outcome (documents themselves are deleted after a decision; reviewer ids are not included).'),
	('training_surveys', 'user_id', 'exported', 'Training survey answers.'),
	('training_limits', 'user_id', 'exported', 'Areas to go easy on, if you opted in.'),
	('training_plans', 'user_id', 'exported', 'Monthly training plans, with their days.'),
	('training_plan_feedback', 'user_id', 'exported', 'Difficulty ratings of plan sessions.');


--
-- Data for Name: privacy_notices; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."privacy_notices" ("consent_type", "version", "title", "body", "is_draft", "published_at") VALUES
	('privacy_notice', '2026-09-17.draft-1', 'Privacy notice', 'Draft — pending institutional/privacy review. Not legal advice.

This notice describes what GymApp does with your data today. It will change after review. When it does, you will be asked to read the new version.

## What the app collects
- Account: your email address and password (handled by Supabase Auth), username and bio.
- Body information you enter: bodyweight (required at signup), and optionally height, sex, age and goal.
- Activity: workouts, sets, reps and the loads you type, XP, ranks, missions, dungeons, gold and shop history.
- Camera workouts: the camera video stays on your device. When you record a reference rep, the joint positions for that one rep are saved to your account. A separate notice is shown before your first camera workout.
- Runs and walks: your location is used on your device to measure distance. Only distance and duration are saved, not your route.
- Meals: the foods, amounts and nutrition you log, your food budget and the prices you enter.
- AI features: see the separate notice shown before you first use them.
- Social: global chat, direct messages, community posts and images, friend requests, and the reports you send.

## Who can see it
- Other users can see your username, bio, rank, stats, your recent workouts on your profile, your lifts in kilograms on the strength leaderboard, and what you post in chat and the community.
- Other users cannot see your bodyweight, height, sex, age or goal. The relative (bodyweight) leaderboard only includes you if you join it.
- Moderators and admins can see reports, bug reports, community posts waiting for approval, and a list of accounts with their roles.

## Where it is stored and sent
- Your account and data are stored with Supabase, in its Australia (Sydney) region.
- The pose model and fonts are downloaded from Google, and the pose-detection code from jsDelivr. They receive your device''s IP address, not your workout data.
- During runs and walks, map images load from OpenStreetMap, which receives the map area shown.
- Food searches are sent to USDA FoodData Central.
- AI features send data to a self-hosted AI server through an ngrok tunnel, as described in the AI notice.

## How long it is kept
Your data is kept until you delete your account. Retention periods have not been set yet. They are part of the review.

## Your choices
- You can edit your profile at any time.
- You can download a copy of your data from your Profile.
- You can deactivate your account (hidden, data kept) or delete it (your data is removed).
- If you delete your account, direct messages you sent or received are deleted for both people, and reports you filed are kept without your name.

## Questions
Use Report a bug, then Other, on your Profile. A formal contact will be added after review.', true, '2026-09-17 09:45:51.456345+00'),
	('camera', '2026-09-17.draft-1', 'Before your first camera workout', 'Draft — pending institutional/privacy review. Not legal advice.

- The camera video is processed on your device. It is never uploaded or saved.
- When you record a reference rep, the positions of the joints that exercise uses, over that one rep, are saved to your account (no images). The app uses them next time. Recording a new rep replaces the old one.
- Each set saves the reps counted and a movement-match score to your workout history.
- The camera tracks joints only. It can''t see weights, machines or your grip, and it doesn''t verify your load.
- When the camera starts, the pose model is downloaded from Google and the detection code from jsDelivr.', true, '2026-09-17 09:45:51.456345+00'),
	('gps', '2026-09-17.draft-1', 'Before your first run or walk', 'Draft — pending institutional/privacy review. Not legal advice.

- While a run or walk is active, your device''s GPS is used to draw your route on the map and measure distance.
- Only the total distance and duration are saved. Your route is not stored.
- The map images load from OpenStreetMap''s servers, which receive the map area shown and your device''s IP address.', true, '2026-09-17 09:45:51.456345+00'),
	('ai_features', '2026-09-17.draft-1', 'Before using AI features', 'Draft — pending institutional/privacy review. Not legal advice.

- AI Suggestions sends your path and rank, your recent exercises and movement scores, your goal, your daily calorie and macro targets (calculated from your body information) and today''s meal totals to an AI model. The suggestions it writes are saved to your account.
- Food photo scan sends the photo to the same AI model to name the food. GymApp does not store the photo.
- The AI model is self-hosted on a private computer run by the app''s developer and reached through an ngrok tunnel. It is not a cloud AI company. Whether that computer keeps logs is part of the review.
- AI suggestions are general text, not medical or dietary advice.', true, '2026-09-17 09:45:51.456345+00'),
	('relative_leaderboard', '2026-09-17.draft-1', 'Join the relative leaderboard?', 'Draft — pending institutional/privacy review. Not legal advice.

- If you join, your best lifts appear on the relative leaderboard as multiples of your bodyweight, with a strength tier.
- Your bodyweight itself is never shown. However, anyone who sees both your lift in kilograms and your bodyweight multiple can work out your approximate bodyweight.
- You can leave at any time from the leaderboard or your Profile. Your relative entries disappear right away.
- Your lifts in kilograms appear on the absolute leaderboard whether or not you join.', true, '2026-09-17 09:45:51.456345+00'),
	('ai_features', '2026-09-17.draft-2', 'Before using AI features', 'Draft — pending institutional/privacy review. Not legal advice.

- AI Suggestions sends your path and rank, your recent exercises and movement scores, your goal, your daily calorie and macro targets (calculated from your body information) and today''s meal totals to an AI model. The suggestions it writes are saved to your account.
- Food photo scan sends the photo to the same AI model to name the food. GymApp does not store the photo.
- The AI model is self-hosted on a developer-controlled computer and reached through an ngrok tunnel. It is not a cloud AI service.
- Whether that computer or ngrok keeps logs of these requests has not been verified yet. This is part of the review.
- AI suggestions are general text, not medical or dietary advice.', true, '2026-09-17 14:14:07.417409+00'),
	('verification', '2026-09-17.draft-1', 'Before applying as a verified coach', 'Draft — pending institutional/privacy review. Not legal advice.

- A coach application has a written summary of your coaching experience and 1 to 3 images of certificates or qualifications. Medals or trophies can be added only as supporting evidence.
- Do not upload body photos, government IDs, or documents showing other people''s personal details. They are not needed and are not used.
- Your phone converts each image to JPEG before upload, which removes location and camera details stored in the photo.
- The images are kept in private storage that only the server can reach. Only admins can view them, through links that expire after 5 minutes, and every view is recorded.
- The images are deleted as soon as an admin approves or rejects your application, when you withdraw it, or when you delete your account.
- A record of the application is kept: your summary, the decision and reason, when it happened, who reviewed it, and a fingerprint (hash) and size of each file. The fingerprint shows which file was reviewed. It does not prove that a certificate is genuine.
- If approved, your profile shows "Verified coach". This is a platform status: GymApp reviewed submitted documents. It is not a guarantee of expertise or professional competence.
- You can remove your coach status at any time, and admins can remove it too. If an application is rejected, you can apply again after 7 days.', true, '2026-09-17 14:47:11.209867+00'),
	('privacy_notice', '2026-09-23.draft-2', 'Privacy notice', 'Draft — pending institutional/privacy review. Not legal advice.

This notice describes what GYMORA does with your data today. It will change after review. When it does, you will be asked to read the new version.

## What the app collects
- Account: your email address and password (handled by Supabase Auth), username and bio.
- Body information you enter: bodyweight (required at signup), and optionally height, sex, age and goal.
- Activity: workouts, sets, reps and the loads you type, XP, ranks, missions, dungeons, gold and shop history.
- Camera workouts: the camera video stays on your device. When you record a reference rep, the joint positions for that one rep are saved to your account. A separate notice is shown before your first camera workout.
- Runs and walks: your location is used on your device to measure distance. Only distance and duration are saved, not your route.
- Meals: the foods, amounts and nutrition you log, your food budget and the prices you enter.
- AI features: see the separate notice shown before you first use them.
- Social: global chat, direct messages, community posts and images, friend requests, and the reports you send.

## Who can see it
- Other users can see your username, bio, rank, stats, your recent workouts on your profile, your lifts in kilograms on the strength leaderboard, and what you post in chat and the community.
- Other users cannot see your bodyweight, height, sex, age or goal. The relative (bodyweight) leaderboard only includes you if you join it.
- Moderators and admins can see reports, bug reports, community posts waiting for approval, and a list of accounts with their roles.

## Where it is stored and sent
- Your account and data are stored with Supabase, in its Australia (Sydney) region.
- The pose model and fonts are downloaded from Google, and the pose-detection code from jsDelivr. They receive your device''s IP address, not your workout data.
- During runs and walks, map images load from OpenStreetMap, which receives the map area shown.
- Food searches are sent to USDA FoodData Central.
- AI features send data to a self-hosted AI server through an ngrok tunnel, as described in the AI notice.

## How long it is kept
Your data is kept until you delete your account. Retention periods have not been set yet. They are part of the review.

## Your choices
- You can edit your profile at any time.
- You can download a copy of your data from your Profile.
- You can deactivate your account (hidden, data kept) or delete it (your data is removed).
- If you delete your account, direct messages you sent or received are deleted for both people, and reports you filed are kept without your name.

## Questions
Use Report a bug, then Other, on your Profile. A formal contact will be added after review.', true, '2026-09-23 15:39:25.7002+00'),
	('ai_features', '2026-09-23.draft-3', 'Before using AI features', 'Draft — pending institutional/privacy review. Not legal advice.

- AI Suggestions sends your path and rank, your recent exercises and movement scores, your goal, your daily calorie and macro targets (calculated from your body information) and today''s meal totals to an AI model. The suggestions it writes are saved to your account.
- Food photo scan sends the photo to the same AI model to name the food. GYMORA does not store the photo.
- The AI model is self-hosted on a developer-controlled computer and reached through an ngrok tunnel. It is not a cloud AI service.
- Whether that computer or ngrok keeps logs of these requests has not been verified yet. This is part of the review.
- AI suggestions are general text, not medical or dietary advice.', true, '2026-09-23 15:39:25.7002+00'),
	('verification', '2026-09-23.draft-2', 'Before applying as a verified coach', 'Draft — pending institutional/privacy review. Not legal advice.

- A coach application has a written summary of your coaching experience and 1 to 3 images of certificates or qualifications. Medals or trophies can be added only as supporting evidence.
- Do not upload body photos, government IDs, or documents showing other people''s personal details. They are not needed and are not used.
- Your phone converts each image to JPEG before upload, which removes location and camera details stored in the photo.
- The images are kept in private storage that only the server can reach. Only admins can view them, through links that expire after 5 minutes, and every view is recorded.
- The images are deleted as soon as an admin approves or rejects your application, when you withdraw it, or when you delete your account.
- A record of the application is kept: your summary, the decision and reason, when it happened, who reviewed it, and a fingerprint (hash) and size of each file. The fingerprint shows which file was reviewed. It does not prove that a certificate is genuine.
- If approved, your profile shows "Verified coach". This is a platform status: GYMORA reviewed submitted documents. It is not a guarantee of expertise or professional competence.
- You can remove your coach status at any time, and admins can remove it too. If an application is rejected, you can apply again after 7 days.', true, '2026-09-23 15:39:25.7002+00'),
	('privacy_notice', '2026-09-24.draft-3', 'Privacy notice', 'Draft — pending institutional/privacy review. Not legal advice.

This notice describes what GYMORA does with your data today. It will change after review. When it does, you will be asked to read the new version.

## What the app collects
- Account: your email address and password (handled by Supabase Auth), username and bio.
- Body information you enter: bodyweight (required at signup), and optionally height, sex, age and goal.
- Activity: workouts, sets, reps and the loads you type, XP, ranks, missions, dungeons, gold and shop history.
- Camera workouts: the camera video stays on your device. When you record a reference rep, the joint positions for that one rep are saved to your account. A separate notice is shown before your first camera workout.
- Runs and walks: your location is used on your device to measure distance. Only distance and duration are saved to your account. Your routes are kept only on your device, for your personal heatmap and the route images you choose to share, and are never uploaded.
- Meals: the foods, amounts and nutrition you log, your food budget and the prices you enter.
- Training plan: your survey answers (goal, experience, training days, session length, equipment and camera preference), the monthly plan made from them, which days you completed or skipped, and your difficulty ratings. Areas to go easy on are stored only if you opt in; a separate notice explains them.
- AI features: see the separate notice shown before you first use them.
- Social: global chat, direct messages, community posts and images, friend requests, and the reports you send.

## Who can see it
- Other users can see your username, bio, rank, stats, your recent workouts on your profile, your lifts in kilograms on the strength leaderboard, and what you post in chat and the community.
- Other users cannot see your bodyweight, height, sex, age or goal. The relative (bodyweight) leaderboard only includes you if you join it.
- Moderators and admins can see reports, bug reports, community posts waiting for approval, and a list of accounts with their roles.

## Where it is stored and sent
- Your account and data are stored with Supabase, in its Australia (Sydney) region.
- The pose model and fonts are downloaded from Google, and the pose-detection code from jsDelivr. They receive your device''s IP address, not your workout data.
- During runs and walks, map images load from OpenStreetMap, which receives the map area shown.
- Food searches are sent to USDA FoodData Central.
- AI features send data to a self-hosted AI server through an ngrok tunnel, as described in the AI notice.

## How long it is kept
Your data is kept until you delete your account. Retention periods have not been set yet. They are part of the review.

## Your choices
- You can edit your profile at any time.
- You can download a copy of your data from your Profile.
- You can deactivate your account (hidden, data kept) or delete it (your data is removed).
- If you delete your account, direct messages you sent or received are deleted for both people, and reports you filed are kept without your name.

## Questions
Use Report a bug, then Other, on your Profile. A formal contact will be added after review.', true, '2026-09-24 01:48:09.846352+00'),
	('training_limits', '2026-09-24.draft-1', 'Areas to go easy on', 'Draft — pending institutional/privacy review. Not legal advice.

- This is optional. If you turn it on, you can tell GYMORA which areas to go easy on: knees, lower back or shoulders.
- This is health information. It is used only to leave exercises out of your monthly plan when they are not marked safe for those areas.
- It is never sent to the AI features and is not shown to other users.
- Exercise safety labels come from the RepDB exercise dataset. An exercise with no label for an area is left out.
- This is not medical advice. The app cannot see your body or how an exercise feels. If you have an injury or a medical condition, check with a doctor or physiotherapist before training.
- You can turn it off at any time from your plan. Your answers are deleted straight away. They are also included in your data download and deleted with your account.', true, '2026-09-24 01:48:09.846352+00'),
	('ai_features', '2026-09-24.draft-4', 'Before using AI features', 'Draft — pending institutional/privacy review. Not legal advice.

- AI Suggestions sends your path and rank, your recent exercises and movement scores, your goal, your daily calorie and macro targets (calculated from your body information) and today''s meal totals to an AI model. The suggestions it writes are saved to your account.
- Plan tips sends your training goal, experience, training days per week, session length and equipment, and the names of your plan''s sessions and exercises. It never sends the areas you asked to go easy on. Plan tips are not saved.
- Food photo scan sends the photo to the same AI model to name the food. GYMORA does not store the photo.
- The AI model is self-hosted on a developer-controlled computer and reached through an ngrok tunnel. It is not a cloud AI service.
- Whether that computer or ngrok keeps logs of these requests has not been verified yet. This is part of the review.
- AI suggestions are general text, not medical or dietary advice.', true, '2026-09-24 01:52:01.584724+00'),
	('privacy_notice', '2026-09-25.draft-4', 'Privacy notice', 'Draft — pending institutional/privacy review. Not legal advice.

This notice describes what AWXCEND does with your data today. It will change after review. When it does, you will be asked to read the new version.

## What the app collects
- Account: your email address and password (handled by Supabase Auth), username and bio.
- Body information you enter: bodyweight (required at signup), and optionally height, sex, age and goal.
- Activity: workouts, sets, reps and the loads you type, XP, ranks, missions, dungeons, gold and shop history.
- Camera workouts: the camera video stays on your device. When you record a reference rep, the joint positions for that one rep are saved to your account. A separate notice is shown before your first camera workout.
- Runs and walks: your location is used on your device to measure distance. Only distance and duration are saved to your account. Your routes are kept only on your device, for your personal heatmap and the route images you choose to share, and are never uploaded.
- Meals: the foods, amounts and nutrition you log, your food budget and the prices you enter.
- Training plan: your survey answers (goal, experience, training days, session length, equipment and camera preference), the monthly plan made from them, which days you completed or skipped, and your difficulty ratings. Areas to go easy on are stored only if you opt in; a separate notice explains them.
- AI features: see the separate notice shown before you first use them.
- Social: global chat, direct messages, community posts and images, friend requests, and the reports you send.

## Who can see it
- Other users can see your username, bio, rank, stats, your recent workouts on your profile, your lifts in kilograms on the strength leaderboard, and what you post in chat and the community.
- Other users cannot see your bodyweight, height, sex, age or goal. The relative (bodyweight) leaderboard only includes you if you join it.
- Moderators and admins can see reports, bug reports, community posts waiting for approval, and a list of accounts with their roles.

## Where it is stored and sent
- Your account and data are stored with Supabase, in its Australia (Sydney) region.
- The pose model and fonts are downloaded from Google, and the pose-detection code from jsDelivr. They receive your device''s IP address, not your workout data.
- During runs and walks, map images load from OpenStreetMap, which receives the map area shown.
- Food searches are sent to USDA FoodData Central.
- AI features send data to a self-hosted AI server through an ngrok tunnel, as described in the AI notice.

## How long it is kept
Your data is kept until you delete your account. Retention periods have not been set yet. They are part of the review.

## Your choices
- You can edit your profile at any time.
- You can download a copy of your data from your Profile.
- You can deactivate your account (hidden, data kept) or delete it (your data is removed).
- If you delete your account, direct messages you sent or received are deleted for both people, and reports you filed are kept without your name.

## Questions
Use Report a bug, then Other, on your Profile. A formal contact will be added after review.', true, '2026-09-25 00:37:36.04772+00'),
	('ai_features', '2026-09-25.draft-5', 'Before using AI features', 'Draft — pending institutional/privacy review. Not legal advice.

- AI Suggestions sends your path and rank, your recent exercises and movement scores, your goal, your daily calorie and macro targets (calculated from your body information) and today''s meal totals to an AI model. The suggestions it writes are saved to your account.
- Plan tips sends your training goal, experience, training days per week, session length and equipment, and the names of your plan''s sessions and exercises. It never sends the areas you asked to go easy on. Plan tips are not saved.
- Food photo scan sends the photo to the same AI model to name the food. AWXCEND does not store the photo.
- The AI model is self-hosted on a developer-controlled computer and reached through an ngrok tunnel. It is not a cloud AI service.
- Whether that computer or ngrok keeps logs of these requests has not been verified yet. This is part of the review.
- AI suggestions are general text, not medical or dietary advice.', true, '2026-09-25 00:37:36.04772+00'),
	('verification', '2026-09-25.draft-3', 'Before applying as a verified coach', 'Draft — pending institutional/privacy review. Not legal advice.

- A coach application has a written summary of your coaching experience and 1 to 3 images of certificates or qualifications. Medals or trophies can be added only as supporting evidence.
- Do not upload body photos, government IDs, or documents showing other people''s personal details. They are not needed and are not used.
- Your phone converts each image to JPEG before upload, which removes location and camera details stored in the photo.
- The images are kept in private storage that only the server can reach. Only admins can view them, through links that expire after 5 minutes, and every view is recorded.
- The images are deleted as soon as an admin approves or rejects your application, when you withdraw it, or when you delete your account.
- A record of the application is kept: your summary, the decision and reason, when it happened, who reviewed it, and a fingerprint (hash) and size of each file. The fingerprint shows which file was reviewed. It does not prove that a certificate is genuine.
- If approved, your profile shows "Verified coach". This is a platform status: AWXCEND reviewed submitted documents. It is not a guarantee of expertise or professional competence.
- You can remove your coach status at any time, and admins can remove it too. If an application is rejected, you can apply again after 7 days.', true, '2026-09-25 00:37:36.04772+00'),
	('training_limits', '2026-09-25.draft-2', 'Areas to go easy on', 'Draft — pending institutional/privacy review. Not legal advice.

- This is optional. If you turn it on, you can tell AWXCEND which areas to go easy on: knees, lower back or shoulders.
- This is health information. It is used only to leave exercises out of your monthly plan when they are not marked safe for those areas.
- It is never sent to the AI features and is not shown to other users.
- Exercise safety labels come from the RepDB exercise dataset. An exercise with no label for an area is left out.
- This is not medical advice. The app cannot see your body or how an exercise feels. If you have an injury or a medical condition, check with a doctor or physiotherapist before training.
- You can turn it off at any time from your plan. Your answers are deleted straight away. They are also included in your data download and deleted with your account.', true, '2026-09-25 00:37:36.04772+00');


--
-- Data for Name: rank_thresholds; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."rank_thresholds" ("id", "rank_name", "focus_type", "min_xp", "tier_index", "sub_ranks", "sub_rank_span_xp") VALUES
	('8f82a32e-a0d1-4091-9399-e26f42f199b4', 'Beginner', 'hybrid', 0, 1, 5, NULL),
	('0079ceb3-a9ed-4304-b192-567dba72b7f8', 'Iron Rookie', 'powerlifter', 0, 1, 5, NULL),
	('327ebfea-a27e-40d9-9805-5c3a948ac2ee', 'Floor Newbie', 'cali', 0, 1, 5, NULL),
	('31a0f3eb-6e25-441a-bddd-48249579a117', 'Mirror Chaser', 'aesthetic', 0, 1, 5, NULL),
	('61cf930a-65e9-4cbd-8610-77bc2c56be80', 'Plate Novice', 'weightlifter', 0, 1, 5, NULL),
	('a910e927-8cfe-4d85-a2ac-acca95f1ac92', 'Anvil Novice', 'strongman', 0, 1, 5, NULL),
	('9a9e80b3-d19a-4a6b-ab8f-78607ac078d4', 'Cadet', 'tactical', 0, 1, 5, NULL),
	('4b64bcb7-ef7c-41d9-ba4c-2c1e27b62d97', 'Pump Rookie', 'hypertrophy', 0, 1, 5, NULL),
	('7d5e9faf-cdcc-4c30-8c31-c8eb63990389', 'Casual Walker', 'lifestyle', 0, 1, 5, NULL),
	('c16c986d-1166-4d0e-bab5-864863535423', 'Cross Trainer', 'hybrid', 1000, 2, 5, NULL),
	('1498f782-2560-4406-879c-93def1022383', 'Plate Pusher', 'powerlifter', 1000, 2, 5, NULL),
	('2b186bb1-6bd4-4384-a330-182f78054575', 'Bar Hanger', 'cali', 1000, 2, 5, NULL),
	('6b88caa7-a8a5-4985-be2a-7d6c5272688a', 'Shape Builder', 'aesthetic', 1000, 2, 5, NULL),
	('57ff036c-7488-49cf-b419-02fe15a58e08', 'Platform Apprentice', 'weightlifter', 1000, 2, 5, NULL),
	('3c95b2d8-83d0-4228-b3fa-e2a2891bbbb4', 'Stone Lifter', 'strongman', 1000, 2, 5, NULL),
	('f2a50d20-ef07-49f4-b98d-8617a3728ad1', 'Operator', 'tactical', 1000, 2, 5, NULL),
	('06507989-ac73-4d02-b9cd-eec2355b8715', 'Tension Builder', 'hypertrophy', 1000, 2, 5, NULL),
	('909bc940-7f09-4587-bd75-1e50c3f1011f', 'Active Mover', 'lifestyle', 1000, 2, 5, NULL),
	('d214acce-2a9f-45bc-90e2-83e69e1135c0', 'Hybrid Athlete', 'hybrid', 3000, 3, 5, NULL),
	('0c7a7871-df25-43f3-970d-86b1da70a113', 'Strength Seeker', 'powerlifter', 3000, 3, 5, NULL),
	('b8429a5f-5535-477f-af1b-1db874d613c9', 'Skill Grinder', 'cali', 3000, 3, 5, NULL),
	('dc23c10d-cf28-4ff0-ae01-b1c696b8ac56', 'Physique Artist', 'aesthetic', 3000, 3, 5, NULL),
	('493542dc-316b-4328-b352-72186039f031', 'Snatch Specialist', 'weightlifter', 3000, 3, 5, NULL),
	('0d9b944d-95b1-406d-8fc9-23df180f2977', 'Yoke Carrier', 'strongman', 3000, 3, 5, NULL),
	('7fec227b-065b-4ecf-a4ad-0f3d8c9923cb', 'Field Veteran', 'tactical', 3000, 3, 5, NULL),
	('a2fe4954-7b57-4f11-abaf-4c01dea1ea91', 'Volume Chaser', 'hypertrophy', 3000, 3, 5, NULL),
	('1141ec78-ad72-426c-987c-eb20fd6df5a3', 'Daily Striver', 'lifestyle', 3000, 3, 5, NULL),
	('2f7aedaf-2ebf-469d-914d-5f80be4c1af3', 'Hybrid Elite', 'hybrid', 7500, 4, 5, NULL),
	('dc481405-483b-4177-b5b7-bf3c474211bc', 'Powerlifter', 'powerlifter', 7500, 4, 5, NULL),
	('2225168b-a0df-4487-8486-cdb24573bef4', 'Calisthenics', 'cali', 7500, 4, 5, NULL),
	('cac1d914-117f-4db5-8895-322fef7937a5', 'Aesthetic', 'aesthetic', 7500, 4, 5, NULL),
	('49ff5342-3c20-4a37-b819-92d6853d98e0', 'Clean Master', 'weightlifter', 7500, 4, 5, NULL),
	('822829a1-8fd6-4b63-9f6c-8d0a20bd0399', 'Axle Breaker', 'strongman', 7500, 4, 5, NULL),
	('afef0c04-3eb2-41d9-b1af-aa05faa57622', 'Vanguard', 'tactical', 7500, 4, 5, NULL),
	('c0edc7e4-a501-4201-897e-9b0ac87d2827', 'Muscle Sculptor', 'hypertrophy', 7500, 4, 5, NULL),
	('894ad138-16a5-4dca-a23e-adf91e07d014', 'Fitness Enthusiast', 'lifestyle', 7500, 4, 5, NULL),
	('6224b57f-e10f-4963-8965-0374aa85f78b', 'Shadow Hybrid', 'hybrid', 15000, 5, 5, NULL),
	('fe115d7c-fbc0-4ccd-a5f8-affa6936b5db', 'Iron Captain', 'powerlifter', 15000, 5, 5, NULL),
	('5dec67d8-0c8b-4d0f-bca9-7caedaa9dbda', 'Gravity Defier', 'cali', 15000, 5, 5, NULL),
	('36ff45b2-4e05-4592-93bf-b843597d4038', 'Iron Sculptor', 'aesthetic', 15000, 5, 5, NULL),
	('c73ab4e1-08b1-440a-979b-8f6adfec9f48', 'Jerk Specialist', 'weightlifter', 15000, 5, 5, NULL),
	('1e8e6627-9ca5-4c67-bc69-188a6b681a1d', 'Titan Hauler', 'strongman', 15000, 5, 5, NULL),
	('9d47f7af-3d2c-46da-9a26-3b4ce5fbd3cd', 'Task Force Elite', 'tactical', 15000, 5, 5, NULL),
	('a5f4487b-0458-4c96-89de-df48df2b2d7d', 'Mass Constructor', 'hypertrophy', 15000, 5, 5, NULL),
	('ac1272ce-c296-4ab8-96fc-cd9ede15d5a5', 'Wellness Journeyman', 'lifestyle', 15000, 5, 5, NULL),
	('5da37dbb-8437-49b9-91f4-56e9d45de347', 'Prime Hybrid', 'hybrid', 25000, 6, 5, NULL),
	('962f97dc-b473-4d0a-a652-4b3993fb2ca2', 'Barbell Warlord', 'powerlifter', 25000, 6, 5, NULL),
	('0c77e349-e185-418c-b39b-23854cfdcf0f', 'Bar Monarch', 'cali', 25000, 6, 5, NULL),
	('a098bd4f-a807-4dd6-aed6-c239a000a842', 'Proportion God', 'aesthetic', 25000, 6, 5, NULL),
	('d1b4a670-340d-462e-aaa9-5642f2640a2e', 'Barbell Architect', 'weightlifter', 25000, 6, 5, NULL),
	('d1b24a51-2c99-45b3-9e4c-c1941f5ee04b', 'Heavyweight Brute', 'strongman', 25000, 6, 5, NULL),
	('2f29af1a-07bb-4779-a20e-349bf5f290f6', 'Special Ops', 'tactical', 25000, 6, 5, NULL),
	('ece28379-3e2b-4fab-a079-8b7042bfded6', 'Density Master', 'hypertrophy', 25000, 6, 5, NULL),
	('b4ed26b7-fa76-4b69-86ec-92ca1b3e0512', 'Life Balancer', 'lifestyle', 25000, 6, 5, NULL),
	('68e3c79a-3263-4455-93cb-024d8417f7bd', 'Apex Hybrid', 'hybrid', 38000, 7, 5, NULL),
	('aa474369-54eb-47c7-93f0-410fabc1483a', 'Apex Lifter', 'powerlifter', 38000, 7, 5, NULL),
	('42df8469-9548-4c7d-9286-47dafbef7eeb', 'Apex Gymnastic', 'cali', 38000, 7, 5, NULL),
	('17d44277-0fe5-4935-80f5-51b00140cb00', 'Apex Physique', 'aesthetic', 38000, 7, 5, NULL),
	('ec49f83f-3b4f-4f3d-96b5-cc794695137f', 'Apex Platform', 'weightlifter', 38000, 7, 5, NULL),
	('38f2df34-4e44-4699-af26-8118d7caae71', 'Apex Juggernaut', 'strongman', 38000, 7, 5, NULL),
	('1aa1435a-6a87-4666-a1bd-d1234c8f24dd', 'Apex Pathfinder', 'tactical', 38000, 7, 5, NULL),
	('1b6fd8c5-74e2-4220-9b33-39a8fd5b6598', 'Apex Builder', 'hypertrophy', 38000, 7, 5, NULL),
	('86357c5c-9dcc-4675-aba8-35fb6775b5ba', 'Vitality Master', 'lifestyle', 38000, 7, 5, NULL),
	('fb27c4fe-1b23-441a-854a-6eefb1b2930b', 'Hybrid Sovereign', 'hybrid', 50000, 8, 10, 4000),
	('2eeedfb7-309e-4c98-af8f-c029ec48f0bb', 'Iron Monarch', 'powerlifter', 50000, 8, 10, 4000),
	('01ad0a54-6143-4a3d-a878-d634f44b7a5f', 'Shadow Sovereign', 'cali', 50000, 8, 10, 4000),
	('a0d335e5-2898-4e7c-9dc8-6a4fdda20ca4', 'Aesthetic Deity', 'aesthetic', 50000, 8, 10, 4000),
	('d0df595e-aef3-450a-89f2-1b2384322315', 'Platform Sovereign', 'weightlifter', 50000, 8, 10, 4000),
	('33b50190-646d-4a9c-b367-4cf2de34c2da', 'Titan Monarch', 'strongman', 50000, 8, 10, 4000),
	('1bbf9fa1-4e8f-46a4-b995-743ceed7fd8b', 'Operational Sovereign', 'tactical', 50000, 8, 10, 4000),
	('861308cc-b609-4c99-81c2-6602866a2046', 'Hypertrophy Monarch', 'hypertrophy', 50000, 8, 10, 4000),
	('cb741027-636e-48a9-a19b-0df3444dec22', 'Lifestyle Legend', 'lifestyle', 50000, 8, 10, 4000);


--
-- Data for Name: shop_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."shop_items" ("key", "kind", "name", "description", "price_gold", "max_stack", "purchase_cooldown_seconds", "use_cooldown_seconds", "scope", "effect", "is_active", "sort_order") VALUES
	('health_potion', 'health_potion', 'Health Potion', 'Restores combat HP between objectives in a Dungeon.', 150, 5, 0, 60, 'dungeon', '{"heal_hp": 40}', true, 1),
	('revive_potion', 'revive_potion', 'Revive Potion', 'Brings you back into a Dungeon fight after you go down, where the Dungeon allows it.', 400, 2, 3600, 0, 'dungeon', '{"revive_hp": 50}', true, 2),
	('rest_potion', 'rest_potion', 'Rest Potion', 'Buys extra recovery time inside a Dungeon.', 250, 3, 0, 300, 'dungeon', '{"extend_seconds": 60}', true, 3),
	('pause_potion', 'pause_potion', 'Pause Potion', 'Pauses a Mission for a short while. Missions only.', 200, 3, 0, 0, 'mission', '{"pause_seconds": 120}', true, 4),
	('streak_restore', 'streak_restore', 'Streak Restore', 'Covers one missed day so a broken daily streak carries on.', 300, 2, 86400, 0, 'global', '{"restore_days": 1}', true, 5);


--
-- Data for Name: specialization_affinity; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."specialization_affinity" ("id", "focus_type", "match_type", "match_value", "multiplier", "created_at") VALUES
	('c16ace9a-9686-4e43-a2de-425086fae391', 'powerlifter', 'attribute', 'strength', 1.05, '2026-09-10 06:30:22.089123+00'),
	('fad688ae-fd34-439b-b545-6b2676d6e15a', 'powerlifter', 'exercise', 'squat', 1.35, '2026-09-10 06:30:22.089123+00'),
	('06bb0e3e-195e-448a-9b52-91dae62df380', 'powerlifter', 'exercise', 'benchpress', 1.35, '2026-09-10 06:30:22.089123+00'),
	('12da1bba-03b6-4ce9-acde-523f31f5a4c6', 'powerlifter', 'exercise', 'deadlift', 1.35, '2026-09-10 06:30:22.089123+00'),
	('161e8064-d60e-4693-a392-051409bdf6f1', 'powerlifter', 'exercise', 'romaniandeadlift', 1.15, '2026-09-10 06:30:22.089123+00'),
	('88f22a0f-ce7f-4e8f-8ad1-c748a12be158', 'powerlifter', 'exercise', 'inclinebenchpress', 1.10, '2026-09-10 06:30:22.089123+00'),
	('ec3d98e8-22e5-4d28-a779-492fa91b1eff', 'powerlifter', 'exercise', 'declinebenchpress', 1.10, '2026-09-10 06:30:22.089123+00'),
	('1439492d-8ea0-41d4-be08-37c2a7447854', 'powerlifter', 'exercise', 'jogging', 0.85, '2026-09-10 06:30:22.089123+00'),
	('7573f21a-d3ac-445f-9bef-01ef8c1edcf7', 'powerlifter', 'exercise', 'walking', 0.85, '2026-09-10 06:30:22.089123+00'),
	('dd379c94-6011-4c81-86bd-714c32b5506c', 'powerlifter', 'exercise', 'cycling', 0.85, '2026-09-10 06:30:22.089123+00'),
	('d69e701e-2dfa-4442-a361-7f69a00fe0b8', 'cali', 'attribute', 'agility', 1.05, '2026-09-10 06:30:22.089123+00'),
	('49370b71-3557-4a57-a9f0-086a39b633ce', 'cali', 'exercise', 'pullup', 1.40, '2026-09-10 06:30:22.089123+00'),
	('cba30364-e254-49cb-a1c5-7f9e748e665f', 'cali', 'exercise', 'pushup', 1.35, '2026-09-10 06:30:22.089123+00'),
	('7ceebdcf-4876-44b6-8032-76de5ab7a1eb', 'cali', 'exercise', 'tricepdips', 1.35, '2026-09-10 06:30:22.089123+00'),
	('5f88d582-41ea-41ec-8a83-90ff01f98017', 'cali', 'exercise', 'legraises', 1.25, '2026-09-10 06:30:22.089123+00'),
	('67b43b24-7320-4f4a-8b60-a657ac27a113', 'cali', 'exercise', 'plank', 1.20, '2026-09-10 06:30:22.089123+00'),
	('0a6cea71-60a2-4754-b2b9-58ae2a3ba1ac', 'cali', 'exercise', 'mountainclimbers', 1.15, '2026-09-10 06:30:22.089123+00'),
	('3aa01b06-0668-4f1c-b01b-506c32a36e70', 'cali', 'exercise', 'latpulldown', 0.85, '2026-09-10 06:30:22.089123+00'),
	('ebcfae37-a7f0-45e7-98aa-87aee3bc79ce', 'cali', 'exercise', 'chestflymachine', 0.85, '2026-09-10 06:30:22.089123+00'),
	('d81d4c16-f61e-4f02-bc39-ef2b1884febe', 'cali', 'exercise', 'legextension', 0.85, '2026-09-10 06:30:22.089123+00'),
	('b421da3a-f2ee-4775-ba98-2ff381805ec2', 'cali', 'exercise', 'triceppushdown', 0.85, '2026-09-10 06:30:22.089123+00'),
	('c9d457ac-ab45-4ebe-800c-bbf9d773fcff', 'aesthetic', 'attribute', 'vitality', 1.05, '2026-09-10 06:30:22.089123+00'),
	('6b680d2c-ae51-47d7-bbc0-6d96356884ba', 'aesthetic', 'exercise', 'lateralraise', 1.30, '2026-09-10 06:30:22.089123+00'),
	('7d178d8d-439f-4de8-bfae-059be758075a', 'aesthetic', 'exercise', 'chestflymachine', 1.25, '2026-09-10 06:30:22.089123+00'),
	('c4fe2936-2b72-45f3-be3d-9a77d4573832', 'aesthetic', 'exercise', 'triceppushdown', 1.25, '2026-09-10 06:30:22.089123+00'),
	('e054e3b3-0366-423a-9b07-91397ffc4e4c', 'aesthetic', 'exercise', 'barbellbicepscurl', 1.25, '2026-09-10 06:30:22.089123+00'),
	('6144f6ea-7a8f-4c8a-9300-6783b218e755', 'aesthetic', 'exercise', 'hammercurl', 1.20, '2026-09-10 06:30:22.089123+00'),
	('463b03a4-5669-4298-bace-4386a713ae37', 'aesthetic', 'exercise', 'legextension', 1.20, '2026-09-10 06:30:22.089123+00'),
	('a68c14d8-6bad-467e-a58d-e78bb0f50757', 'aesthetic', 'exercise', 'latpulldown', 1.15, '2026-09-10 06:30:22.089123+00'),
	('d406e37c-3894-4d03-8e74-8ad7b8b59faa', 'weightlifter', 'attribute', 'strength', 1.05, '2026-09-10 06:30:22.089123+00'),
	('dd88db6b-ee01-4844-8e05-8fcea078b22c', 'weightlifter', 'exercise', 'shoulderpress', 1.35, '2026-09-10 06:30:22.089123+00'),
	('5abcc23f-86b6-4289-bcbd-a5d3a7b87ae0', 'weightlifter', 'exercise', 'squat', 1.25, '2026-09-10 06:30:22.089123+00'),
	('0be62ce3-60f7-42cc-ad24-348bf73adbb8', 'weightlifter', 'exercise', 'deadlift', 1.20, '2026-09-10 06:30:22.089123+00'),
	('1123cc5b-1635-42dd-aff0-9451f6e23197', 'weightlifter', 'exercise', 'burpee', 1.10, '2026-09-10 06:30:22.089123+00'),
	('4eae9aee-a10e-46fe-9fa2-6b647bdfc164', 'strongman', 'attribute', 'strength', 1.10, '2026-09-10 06:30:22.089123+00'),
	('7a87319f-7fe1-4c45-817c-640831aed30e', 'strongman', 'exercise', 'deadlift', 1.35, '2026-09-10 06:30:22.089123+00'),
	('89efd93a-337c-4188-89af-35b531865b46', 'strongman', 'exercise', 'tbarrow', 1.25, '2026-09-10 06:30:22.089123+00'),
	('af33b118-e148-4de1-9198-d0dbfc4fd3b4', 'strongman', 'exercise', 'hipthrust', 1.20, '2026-09-10 06:30:22.089123+00'),
	('89e9a006-5596-49b1-996e-c6229e1829d5', 'strongman', 'exercise', 'squat', 1.20, '2026-09-10 06:30:22.089123+00'),
	('08413ff5-5178-42bc-94f5-6facc1054f12', 'strongman', 'exercise', 'shoulderpress', 1.15, '2026-09-10 06:30:22.089123+00'),
	('fd0f1f7c-62ac-45b8-9f92-c31c51680b79', 'tactical', 'attribute', 'agility', 1.10, '2026-09-10 06:30:22.089123+00'),
	('6d2b4905-2cec-43de-9c28-f9ca3b5d13b4', 'tactical', 'attribute', 'vitality', 1.10, '2026-09-10 06:30:22.089123+00'),
	('25cedbf6-a45f-432d-a334-618f536f5529', 'tactical', 'exercise', 'jogging', 1.35, '2026-09-10 06:30:22.089123+00'),
	('7b5de99e-e03a-467a-97b1-655c686d5854', 'tactical', 'exercise', 'burpee', 1.30, '2026-09-10 06:30:22.089123+00'),
	('fec41805-5806-4fdd-bcb2-4ce650524d50', 'tactical', 'exercise', 'walking', 1.25, '2026-09-10 06:30:22.089123+00'),
	('4b869a60-010c-49b8-a873-e1cc177183c5', 'tactical', 'exercise', 'mountainclimbers', 1.25, '2026-09-10 06:30:22.089123+00'),
	('64fc95ec-37ca-4df7-93a1-ae71cbae774e', 'tactical', 'exercise', 'plank', 1.25, '2026-09-10 06:30:22.089123+00'),
	('c8a2e4b1-ce23-401f-9f44-afce81394487', 'tactical', 'exercise', 'pushup', 1.20, '2026-09-10 06:30:22.089123+00'),
	('9ea477f7-3910-42af-8eae-c765de8f7807', 'tactical', 'exercise', 'pullup', 1.20, '2026-09-10 06:30:22.089123+00'),
	('a15d1f19-e492-4070-82d8-ebe7bb7a16b9', 'tactical', 'exercise', 'shadowboxing', 1.15, '2026-09-10 06:30:22.089123+00'),
	('1249ca55-705f-44d8-95a6-a8beecb7aedf', 'hypertrophy', 'attribute', 'vitality', 1.10, '2026-09-10 06:30:22.089123+00'),
	('c0e91db9-b0e9-48cb-999d-30bc628e6af7', 'hypertrophy', 'attribute', 'strength', 1.05, '2026-09-10 06:30:22.089123+00'),
	('26edb3a4-e4a1-4bcd-97db-375267a3ee88', 'hypertrophy', 'exercise', 'barbellbicepscurl', 1.30, '2026-09-10 06:30:22.089123+00'),
	('ed27aaab-22bb-405c-aed6-9f865728aa19', 'hypertrophy', 'exercise', 'hammercurl', 1.30, '2026-09-10 06:30:22.089123+00'),
	('78b0b60e-89de-46a2-a86c-69491898e1e3', 'hypertrophy', 'exercise', 'triceppushdown', 1.30, '2026-09-10 06:30:22.089123+00'),
	('16725344-e33f-489c-b24a-746b7665ee3c', 'hypertrophy', 'exercise', 'chestflymachine', 1.30, '2026-09-10 06:30:22.089123+00'),
	('538dc709-da77-4b38-8548-9983189e03ae', 'hypertrophy', 'exercise', 'legextension', 1.30, '2026-09-10 06:30:22.089123+00'),
	('f237cd09-f5fa-4b8c-8c9b-8ded3e51549d', 'hypertrophy', 'exercise', 'lateralraise', 1.25, '2026-09-10 06:30:22.089123+00'),
	('fb340b87-15dc-45d2-9619-6b2b5761928c', 'hypertrophy', 'exercise', 'latpulldown', 1.20, '2026-09-10 06:30:22.089123+00'),
	('239b4733-7ea3-40f0-95d3-9ad8878dc129', 'hypertrophy', 'exercise', 'tbarrow', 1.15, '2026-09-10 06:30:22.089123+00'),
	('0034aa3d-1621-47a5-856f-d72b17a0c3cd', 'hypertrophy', 'exercise', 'jogging', 0.85, '2026-09-10 06:30:22.089123+00'),
	('bf492159-55ad-4db7-bf35-094f6fa73ec3', 'hypertrophy', 'exercise', 'cycling', 0.85, '2026-09-10 06:30:22.089123+00'),
	('a84aada8-b221-4ab9-885a-0f96130c2175', 'lifestyle', 'attribute', 'vitality', 1.15, '2026-09-10 06:30:22.089123+00'),
	('c2e911d5-77a7-49fe-a9c0-117ddd3043b1', 'lifestyle', 'exercise', 'walking', 1.50, '2026-09-10 06:30:22.089123+00'),
	('1fc2b39d-c888-4e9f-ad42-a3b22c27ffbc', 'lifestyle', 'exercise', 'jogging', 1.40, '2026-09-10 06:30:22.089123+00'),
	('c76d318b-cb99-439d-99c8-797762d47565', 'lifestyle', 'exercise', 'cycling', 1.40, '2026-09-10 06:30:22.089123+00'),
	('be8beebd-cceb-4e96-9d56-316344905291', 'weightlifter', 'exercise', 'snatch', 1.45, '2026-09-10 06:47:49.274586+00'),
	('d2474794-57c2-4703-9f17-383936b7bf5c', 'weightlifter', 'exercise', 'cleanandjerk', 1.45, '2026-09-10 06:47:49.274586+00'),
	('b7ae6824-9b00-49ef-bc8f-ca50de5273b8', 'weightlifter', 'exercise', 'powerclean', 1.35, '2026-09-10 06:47:49.274586+00'),
	('86961616-06d9-488a-8e12-575798510c01', 'strongman', 'exercise', 'farmerscarry', 1.40, '2026-09-10 06:47:49.274586+00'),
	('d956fbc9-b486-45fd-a1c6-637955ee8967', 'strongman', 'exercise', 'yokewalk', 1.40, '2026-09-10 06:47:49.274586+00'),
	('93438149-4365-4850-ab2b-c20ce26ac052', 'strongman', 'exercise', 'atlasstone', 1.40, '2026-09-10 06:47:49.274586+00'),
	('ee088713-712d-424c-99fe-66f8ce6c6590', 'tactical', 'exercise', 'rucking', 1.45, '2026-09-10 06:47:49.274586+00'),
	('f4b3ae42-885f-4fa6-888a-5ccee4bdd9de', 'hypertrophy', 'exercise', 'rucking', 0.85, '2026-09-10 06:47:49.274586+00'),
	('bd897467-e0c3-48fe-8b37-07dba5d57025', 'aesthetic', 'exercise', 'tricepdips', 1.25, '2026-09-14 00:58:09.369897+00'),
	('68905c0b-f1a4-4d5d-95bb-34a4f3d22b97', 'hypertrophy', 'exercise', 'tricepdips', 1.25, '2026-09-14 00:58:09.369897+00'),
	('6fe8b0f5-504a-4073-bcaa-18301116f3a2', 'cali', 'exercise', 'sideplank', 1.20, '2026-09-14 00:58:09.369897+00'),
	('121e9597-8cfd-47b6-ba57-2b8b8626106e', 'tactical', 'exercise', 'sideplank', 1.25, '2026-09-14 00:58:09.369897+00'),
	('815e04b4-270b-4abd-9018-9650fabfda0c', 'lifestyle', 'exercise', 'sideplank', 1.20, '2026-09-14 00:58:09.369897+00'),
	('b2bd5625-4841-4aac-b968-97c1ec88734d', 'lifestyle', 'exercise', 'wallsit', 1.30, '2026-09-14 00:58:09.369897+00'),
	('007f07e2-48a3-45f8-afb9-7b8953f9fe6d', 'tactical', 'exercise', 'wallsit', 1.20, '2026-09-14 00:58:09.369897+00'),
	('3df82830-2d08-4e40-a62e-793a2a95b00b', 'cali', 'exercise', 'wallsit', 1.15, '2026-09-14 00:58:09.369897+00');


--
-- Data for Name: threat_ranks; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."threat_ranks" ("key", "label", "sort_order", "is_anomalous", "properties") VALUES
	('C', 'C Rank', 1, false, '{"recommended_party": 1}'),
	('B', 'B Rank', 2, false, '{"recommended_party": 2}'),
	('A', 'A Rank', 3, false, '{"recommended_party": 2}'),
	('S', 'S Rank', 4, false, '{"recommended_party": 3}'),
	('SS', 'SS Rank', 5, false, '{"recommended_party": 3}'),
	('SSS', 'SSS Rank', 6, false, '{"warn_solo": true, "recommended_party": 4}'),
	('unknown', 'Unknown', 7, true, '{"warn_solo": true, "hidden_objectives": true, "recommended_party": 4}'),
	('x', 'X', 8, true, '{"warn_solo": true, "hidden_objectives": true, "recommended_party": 4, "unstable_modifiers": true}');


--
-- Data for Name: xp_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."xp_config" ("id", "workout_source", "exercise_name", "reps_multiplier", "quality_bonus_max", "created_at", "duration_multiplier", "distance_multiplier") VALUES
	('0dbee653-1ead-4625-8e3f-42dcdb42d73e', 'manual', '*', 2.00, 0.00, '2026-07-01 06:06:57.355199+00', NULL, NULL),
	('3c3ad829-85a8-4995-81d8-ae1bf8744895', 'manual', 'squat', 2.40, 0.00, '2026-08-31 21:40:17.1787+00', NULL, NULL),
	('bda015ed-d3a7-4c21-80bf-23686aa5460a', 'manual', 'deadlift', 3.00, 0.00, '2026-08-31 21:40:17.1787+00', NULL, NULL),
	('fae63692-4af8-4f0f-b69e-4d09c1b75c35', 'manual', 'pullup', 2.60, 0.00, '2026-08-31 21:40:17.1787+00', NULL, NULL),
	('fd7b81b8-7f4e-482e-8c1f-dbb0653ba81e', 'manual', 'benchpress', 2.40, 0.00, '2026-08-31 21:40:17.1787+00', NULL, NULL),
	('293bf137-6d95-489a-a660-f0fee4a4742b', 'manual', 'burpee', 2.80, 0.00, '2026-08-31 21:40:17.1787+00', NULL, NULL),
	('a4372445-db7e-473d-97b0-21a3c8776701', 'camera', 'squat', 6.00, 0.50, '2026-08-31 21:40:17.1787+00', NULL, NULL),
	('98066f60-3b14-4d39-b5ad-1c9fb5d56b98', 'manual', 'romaniandeadlift', 2.70, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('c1572ad4-8bcc-48a9-a07e-2a0ecba773c1', 'manual', 'hipthrust', 2.50, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('2965dd40-dc33-4df2-8375-5ba836e540a7', 'manual', 'tbarrow', 2.50, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('e25b300f-30e2-4309-ba9a-7059935e21f4', 'manual', 'inclinebenchpress', 2.30, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('c5f0ca8b-48f4-4b83-9e78-682dc134ccdf', 'manual', 'declinebenchpress', 2.30, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('2aba6d23-d584-4b57-888d-32c0f8b596da', 'manual', 'shoulderpress', 2.30, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('762c23b4-6334-4bea-94f2-669ebe06d7a9', 'manual', 'latpulldown', 2.20, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('f7c1e187-9108-4af5-b5f1-6f9fa47c9387', 'manual', 'tricepdips', 2.20, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('a0c25374-06bf-46ac-a2f9-a500a354fc5a', 'manual', 'legraises', 2.00, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('a685d685-61e5-4c86-b6a1-63e4477f8c76', 'manual', 'russiantwist', 1.80, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('edf6ebeb-78c5-4788-a97f-0226cf9f9fad', 'manual', 'barbellbicepscurl', 1.80, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('9b581906-8b7a-40e1-a0fc-96a271e1e337', 'manual', 'hammercurl', 1.80, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('6cc8a9cf-72e7-4ecc-b999-8ed5d2dbdbb8', 'manual', 'chestflymachine', 1.70, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('77def6b0-ff6e-4458-b72f-3f481915579f', 'manual', 'legextension', 1.70, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('1abf1f78-0635-40f9-9ec2-e9cc79d25671', 'manual', 'triceppushdown', 1.70, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('1ace2e04-0d57-4150-8641-ca700d31c0f9', 'manual', 'lateralraise', 1.60, 0.00, '2026-09-02 23:07:00.710269+00', NULL, NULL),
	('b8544ff8-ef69-4ddb-8bb2-057ce23ede17', 'camera', 'jumpingjacks', 1.50, 0.50, '2026-09-04 05:33:22.279542+00', NULL, NULL),
	('6bad4f6c-fe46-49cf-9364-570ffeeef4a4', 'manual', 'jumpingjacks', 1.20, 0.00, '2026-09-04 05:33:22.279542+00', NULL, NULL),
	('fd6ae39b-d223-46a2-b93a-a2cccc26425f', 'manual', 'jogging', 0.00, 0.00, '2026-09-04 05:33:22.279542+00', 1.50, 45.00),
	('9fc02023-5d10-4de7-b0d2-0393400db1c6', 'manual', 'walking', 0.00, 0.00, '2026-09-04 05:33:22.279542+00', 1.00, 18.00),
	('903b49b4-d75c-43ec-abb7-7ff1a22a7349', 'manual', 'cycling', 0.00, 0.00, '2026-09-04 05:33:22.279542+00', 5.00, 0.00),
	('29880c66-52f2-40f3-8b67-9025a08326ec', 'camera', 'plank', 0.00, 0.50, '2026-09-05 01:22:15.72857+00', 40.00, 0.00),
	('566daab0-5476-4e45-bb69-0395f4c25b12', 'camera', 'shadowboxing', 0.00, 0.50, '2026-09-05 01:22:15.72857+00', 25.00, 0.00),
	('53f5a67b-5860-49fe-b0f9-e61b22168d66', 'manual', 'plank', 0.00, 0.00, '2026-09-05 01:22:15.72857+00', 20.00, 0.00),
	('41ac0636-31d1-426c-891d-372d6f3e1dcc', 'manual', 'shadowboxing', 0.00, 0.00, '2026-09-05 01:22:15.72857+00', 12.00, 0.00),
	('9e2c95e0-39b3-4656-bdfa-e8a47135f286', 'camera', 'mountainclimbers', 1.50, 0.50, '2026-09-05 04:29:20.247738+00', 0.00, 0.00),
	('3f16428d-e7fb-4f41-af83-46d7c2b9c21e', 'manual', 'mountainclimbers', 1.20, 0.00, '2026-09-05 04:29:20.247738+00', 0.00, 0.00),
	('26c5317a-cdab-4877-9467-d13ac4b5a25f', 'manual', 'snatch', 3.40, 0.00, '2026-09-10 06:47:49.274586+00', NULL, NULL),
	('6b57a5d9-e058-4488-ae81-493f783eab9e', 'manual', 'cleanandjerk', 3.30, 0.00, '2026-09-10 06:47:49.274586+00', NULL, NULL),
	('4ae2de3c-1270-4167-8c47-db0e93f447d5', 'manual', 'powerclean', 3.00, 0.00, '2026-09-10 06:47:49.274586+00', NULL, NULL),
	('403b95d2-e769-4d17-aa3d-49359628d33b', 'manual', 'farmerscarry', 3.00, 0.00, '2026-09-10 06:47:49.274586+00', NULL, NULL),
	('dc6160da-850f-446d-8f1a-794558507219', 'manual', 'yokewalk', 2.80, 0.00, '2026-09-10 06:47:49.274586+00', NULL, NULL),
	('e9d0ffcf-5f79-4f92-a2b1-19a4b71da03d', 'manual', 'atlasstone', 3.20, 0.00, '2026-09-10 06:47:49.274586+00', NULL, NULL),
	('a4a11d7b-b058-45ab-b068-99a9be9cd6c3', 'manual', 'rucking', 0.00, 0.00, '2026-09-10 06:47:49.274586+00', 2.00, 30.00),
	('0c45c932-eee4-4d79-ac47-7b03dfaacc15', 'camera', 'sideplank', 0.00, 0.50, '2026-09-14 00:58:09.369897+00', 45.00, 0.00),
	('f06eb028-86b5-4b8f-b55a-1016c7bca662', 'manual', 'sideplank', 0.00, 0.00, '2026-09-14 00:58:09.369897+00', 22.00, 0.00),
	('495235c9-5f79-45ca-9099-b069a4efb26a', 'camera', 'wallsit', 0.00, 0.50, '2026-09-14 00:58:09.369897+00', 35.00, 0.00),
	('6c234d7e-2f97-4f35-a7f7-0bc663827fc3', 'manual', 'wallsit', 0.00, 0.00, '2026-09-14 00:58:09.369897+00', 18.00, 0.00),
	('b9a74a81-9f1e-4c47-af1b-09fc99e2d507', 'camera', 'tricepdips', 4.50, 0.50, '2026-09-14 00:58:09.369897+00', 0.00, 0.00),
	('688be5c0-ff00-494e-b133-be8525ed6d08', 'camera', 'pushup', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('d5fcfdba-f44d-4cc2-a8c4-5f2509e7e403', 'camera', 'lunges', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('f4627482-d528-4fff-bf0e-6b24fdcfa491', 'camera', 'barbellbicepscurl', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('d0789559-64ae-4877-b8a9-f40626930aae', 'camera', 'legraises', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('20bc12f2-4c7c-407c-9b92-4dd29784a5f8', 'camera', 'lateralraise', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('c1af7860-8b46-4c22-8bce-c7b9fd190f4d', 'camera', 'hipthrust', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('75a0e061-a21e-4f39-a709-a5bda397508c', 'camera', 'shoulderpress', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('2924a22c-72de-4916-ac7f-fcf40eee05e4', 'camera', 'deadlift', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('2ca87da6-febd-486f-87bc-34bb662c4de4', 'camera', 'romaniandeadlift', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('e63aa959-12ac-4d96-9574-f82fcd92d836', 'camera', 'pullup', 5.00, 0.50, '2026-09-17 04:38:30.393541+00', NULL, NULL),
	('351c45ac-27df-4e51-a06d-1118f3b65cd8', 'camera', 'latpulldown', 5.00, 0.50, '2026-09-18 05:14:25.703406+00', NULL, NULL),
	('accaf05a-adaa-4c15-9a06-f41a716309f1', 'camera', 'bulgariansplitsquat', 5.00, 0.50, '2026-09-18 05:14:25.703406+00', NULL, NULL);


--
-- PostgreSQL database dump complete
--

-- \unrestrict iB88aUzwRbXrZ42y34qOFq6XA9ZTV52Vvef3UrP5ezCGW6nNftweuWXE5B9z6HJ

RESET ALL;
