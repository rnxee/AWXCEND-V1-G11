# AWXCEND — Python + Flet

A Python + [Flet](https://flet.dev) rebuild of the first version of AWXCEND, a gamified fitness tracker: log workouts, earn XP, climb ranks, track meals, and train with friends.

How we built it, the problems we hit and what we learned: [docs/REBUILD_JOURNAL.md](docs/REBUILD_JOURNAL.md).

## Features

| Area | What it does |
|---|---|
| Account | Sign up (with the privacy notice), log in, reset a password by pasting the emailed link |
| Dashboard | Level and XP progress, rank, streak, quick actions, recent workouts |
| Train | Log any of 35 exercises: sets × reps × weight (kg/lbs), or a duration for timed ones |
| Camera (desktop) | Rep counting for push-ups, squats, lunges and bicep curls, using MediaPipe Pose. The video can come from a webcam or your phone (Phone Link / DroidCam / Iriun as a webcam, or the IP Webcam app over Wi-Fi). **Rotate video** turns a sideways phone feed upright |
| Food | Search foods, log portions by grams or serving, and see today's calories and macros |
| Gymunnity | Fitness and food feed with photos, community chat, friends, direct messages, leaderboard |
| AI coach | Advice from your recent training and meals, after you accept the AI notice |
| Admin | Moderators and admins review reports, the post queue, and user roles |

## Run it (Windows desktop)

```powershell
py -m pip install "flet==0.86.5" httpx opencv-python mediapipe pytest
cd src
py main.py
```

## Tests

```powershell
py -m pytest
```

- `tests/test_counters.py` feeds synthetic poses through the rep counters:
  - real reps count;
  - knee raises, half reps, bounces and tracking dropouts don't.
- `tests/test_api.py` covers the backend client (sign-in, token refresh, error messages) against a fake server.

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

The APK leaves out camera tracking, because MediaPipe for Python doesn't run on Android. `pyproject.toml` excludes the camera files from it. Every other screen works on the phone.

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
- `functions/` holds the 57 Edge Functions.
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
