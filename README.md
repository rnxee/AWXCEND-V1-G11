# AWXCEND — Python + Flet

A Python + [Flet](https://flet.dev) rebuild of the first version of AWXCEND, a gamified fitness tracker: log workouts, earn XP, climb ranks, track meals, and train with friends.

How we built it, the problems we hit and what we learned: [docs/REBUILD_JOURNAL.md](docs/REBUILD_JOURNAL.md).

## Features

| Area | What it does |
|---|---|
| Account | Sign up (18 and over, accepting the Terms of Use and Privacy Policy), log in, reset a password by pasting the emailed link. Account & privacy: download your data, hide your account, delete it, join the relative strength board, report a problem. Legal: Terms of Use, Privacy Policy and Cookie Policy, and a prompt to accept updated versions |
| Dashboard | Level and XP progress, rank, streak, quick actions, recent workouts, and any moderator restrictions on you |
| Train | Log any of 35 exercises: sets × reps × weight (kg/lbs), or a duration for timed ones, and correct or delete a mistake within 24 hours. Routines, a monthly training plan, Missions (boss fights cleared with your sets) and the Dungeon board |
| Profile | Personal records, Shop (spend gold on potions and streak restores), Collection |
| Run / Walk (GPS) | Track a walk, jog or ruck with the phone's GPS: live distance, time and pace, then one workout is logged. Only the total distance and time are saved, never the route. Best on the Android app; a PC's location is too rough to count |
| Camera (desktop) | Rep counting for push-ups, squats, lunges and bicep curls, using MediaPipe Pose. The video can come from a webcam or your phone (Phone Link / DroidCam / Iriun as a webcam, or the IP Webcam app over Wi-Fi). **Rotate video** turns a sideways phone feed upright |
| Food | Search foods, log portions by grams or serving, see today's calories and macros, change the amount of a meal or delete it, and a food budget helper (cheapest protein per peso) |
| Gymunnity | Fitness and food feed with photos, community chat, friends, direct messages (edit your own for 15 minutes, delete any time), XP and strength leaderboards |
| AI coach | Advice from your recent training and meals, after you accept the AI notice |
| Admin | Moderators: reports, post queue, bug reports and **sanctions** (ban an account or restrict posting, chat, DMs, friend requests or reporting, for a set time or permanently). Admins also manage roles and read the audit log |

## Run it (Windows desktop)

```powershell
py -m pip install "flet==0.86.5" "flet-geolocator==0.86.5" httpx opencv-python mediapipe pytest
cd src
py main.py
```

## Offline use

After a player has signed in, AWXCEND keeps an account-scoped local copy of
workouts, meals, cached foods, routines and the current training plan in Flet
SharedPreferences. Workout and meal saves are written locally before a network
request, so airplane mode does not lose them. The Train and Food screens show
pending or failed synchronization states, and the Home screen retries queued
uploads at startup and through its Retry action.

Previously loaded routines and plans remain available offline and show their
last-updated time. Food search still needs the internet for a food that has not
been loaded before. Server-side XP, gold, streaks and validation are only
applied after synchronization; local saves never claim those rewards.

The first deployment of offline upload idempotency requires the versioned
Supabase migration in `backend/supabase/migrations/20261025100000_offline_sync_idempotency.sql`.
Run `npx supabase db push` from `backend/`, then redeploy the changed
`log-workout` and `log-meal` Edge Functions. Existing online requests remain
compatible; until that migration is deployed, local records remain safely
queued rather than being treated as synchronized.

## Tests

```powershell
py -m pytest
```

- `tests/test_counters.py` feeds synthetic poses through the rep counters:
  - real reps count;
  - knee raises, half reps, bounces and tracking dropouts don't.
- `tests/test_replay.py` replays 7 real recorded camera sets; `test_stream.py`, `test_source.py` and `test_orient.py` cover the camera feed.
- `tests/test_api.py` covers the backend client (sign-in, token refresh, password-reset links, bans, error messages) against a fake server.
- `tests/test_auth_screens.py`, `test_features.py` and `test_game.py` drive the real screens against a fake server (`tests/fakes.py`): login and password reset, account deletion, routines, sanctions, deleting workouts and meals, missions and the shop.
- `tests/test_gps.py` and `test_run.py` cover GPS distance (drift, jumps and weak readings don't count) and the Run / Walk screen with a fake GPS.
- `tests/test_ui.py` covers the shared UI helpers (time zones, number fields, dialogs).
- The server's pure rules (sanctions, text cleaning) have their own tests: `node --test backend/supabase/functions/_shared/*.test.ts`.
- GitHub Actions (`.github/workflows/tests.yml`) runs both on every push and pull request. The camera tests skip there because it installs no OpenCV.

The server strips invisible characters (zero-width spaces, text-direction overrides, control codes) from posts, chat and DMs, along with "zalgo" stacks of accent marks. Chat and DM messages are capped at 100 words.

## Build

**Windows app** (no Visual Studio needed, because it uses PyInstaller). The result is `dist\windows\AWXCEND\AWXCEND.exe`. Zip the whole `dist\windows\AWXCEND` folder to share it.

```powershell
py -m pip install pyinstaller
py tools/build_windows.py
```

The script builds with the right options, then runs the packaged app with `--selfcheck`. That loads MediaPipe, the pose model and OpenCV exactly as the camera screen does. If the check fails, the script stops and says so; don't share that build.

To check any build by hand: `AWXCEND.exe --selfcheck result.txt` writes `ok …` or the error to `result.txt`.

**Android APK.** The first run downloads Flutter, a JDK and the Android SDK, a few GB.

```powershell
flet build apk --yes
mkdir dist\android -Force; copy build\apk\awxcend.apk dist\android\
```

`dist\android\awxcend.apk` is the file to install on the phone. Run the Windows and Android builds one after the other, not at the same time.

The APK leaves out camera tracking, because MediaPipe for Python doesn't run on Android. GPS runs and walks do work there: the location add-on is a Flutter package, and `pyproject.toml` asks for foreground location permission only. `pyproject.toml` excludes the camera files from it. Every other screen works on the phone.

## Design

Every screen uses the same "System window" look from `src/ui.py`:
- dark void background with blue and violet auras;
- glass panels with a glowing edge and corner brackets (`ui.card`);
- Michroma titles, `◆ SECTION` headers, and a segmented XP gauge;
- chamfered neon buttons, and lit tabs.

Change colours in `ui.C`, not in the views.

## How it works

- **Client:** `src/`, the Flet UI. Every screen is in `src/views/`.
  - `src/api.py` talks to the backend.
  - `src/pose/` holds the camera pipeline: `camera.py` runs OpenCV and MediaPipe, and `counters.py` holds the pure rep-counting logic.
- **Backend:** Supabase: Postgres with Row Level Security, Auth, and Edge Functions.
  - The app calls `https://<project>.supabase.co/functions/v1/<name>` with the signed-in user's token.
  - XP, ranks, validation and permissions are all enforced by the server, not the app.
- **Rep counting:**
  - Each exercise tracks one joint angle; for a squat, that's the straighter of the two knees.
  - A rep is **top → full depth → back to top**. The gap between the two thresholds stops jitter from double counting.
  - Frames with bad form, such as a swinging elbow on a curl or a push-up that isn't a plank, are skipped rather than counted.
  - Video never leaves the computer.

## Backend (`backend/supabase/`)

The group's Supabase project is `gwtdcxvfvnyfsvnbgneo`.

- `migrations/20260926100000_baseline_schema.sql` holds the full schema: 65 tables, functions, RLS policies and storage buckets.
- `migrations/20260926100100_reference_data.sql` holds the game and food reference data, and no user data.
- `migrations/20260926110000_match_original_privileges.sql` is a security fix. It closes database functions and private tables to the public API; the app reaches them only through Edge Functions. **Every new migration that creates a function must end with** `REVOKE EXECUTE ON FUNCTION public.<name>(<args>) FROM PUBLIC, anon, authenticated;`. Supabase grants everyone access to new functions by default.
- `migrations/20261016120000_user_sanctions.sql` adds moderation sanctions (bans and restrictions). Service role only.
- `migrations/20261016130000_delete_workout_log.sql` lets players delete a hand-logged workout within 24 hours, taking back its XP, rank, attribute points and strength record in one transaction.
- `migrations/20261016140000_close_direct_writes.sql` is a security fix. Routines and camera templates can no longer be written straight through the database API, only through their Edge Functions.
- `migrations/20261016150000_legal_documents.sql` publishes the Terms of Use, Privacy Policy and Cookie Policy. They are versioned and can't be edited once published. To change one, insert a new version: the app then asks every player to accept it.
- `migrations/20261016160000_edit_messages_and_workouts.sql` adds the "edited" marker to chat and direct messages, and `edit_workout_log`: a workout correction done as one transaction that takes the old workout back and logs the new numbers.
- `migrations/20261022100000_gps_notices.sql` publishes the GPS notice shown before a first run, and new versions of the Terms of Use and Privacy Policy that cover location and outdoor safety (everyone is asked to accept them again).
- `functions/` holds the 64 Edge Functions. Bans are checked in `_shared/auth.ts`, so every function refuses a banned player (except export, delete, privacy and abandon-signup: a sanction never blocks a player's rights over their own data). The pure rules are in `_shared/sanctionRules.ts`; test them with `node --test backend/supabase/functions/_shared/sanctionRules.test.ts`.
- After changing anything in `functions/_shared/`, redeploy all functions: each one bundles its own copy.
- `config.toml` holds the auth settings: sign-in without email confirmation and a minimum password length of 8. The free plan can't customise emails without custom SMTP, so the default reset email (a link) is used and the app accepts the pasted link. `templates/recovery.html` (a code email) is ready for when custom SMTP is set up.

Run these from the `backend/` folder:

```powershell
npx supabase link --project-ref gwtdcxvfvnyfsvnbgneo
npx supabase db push                                  # apply new migrations
npx supabase functions deploy --use-api               # redeploy functions
npx supabase secrets set USDA_API_KEY=<your key>      # optional: USDA fallback in food search
npx supabase secrets set OLLAMA_URL=<url> OLLAMA_SECRET=<secret> OLLAMA_MODEL=<model>  # optional: AI coach
```

The functions use the project's built-in `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`, so there's nothing else to set.

## Security

`src/config.py` holds only the project URL and the **publishable** key, which is designed to ship inside apps; RLS protects the data. Never commit a service-role key, a `.env` file, or any other secret.
