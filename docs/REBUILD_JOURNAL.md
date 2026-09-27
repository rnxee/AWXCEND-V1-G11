# AWXCEND rebuild journal: Python + Flet

This is a record of how we rebuilt AWXCEND in Python and Flet between 26 and 27 September 2026. It covers the problems we ran into, how we solved them, and what we learned. To run or build the app, see the [README](../README.md).

## At a glance

| | |
|---|---|
| What | The first version of AWXCEND, a gamified fitness tracker, rebuilt in Python |
| UI framework | [Flet](https://flet.dev) 0.86 (Python on top of Flutter) |
| Platforms | Windows desktop app, and an Android APK |
| Backend | Our own Supabase project: Postgres with Row Level Security, Auth, and 57 Edge Functions |
| Camera | OpenCV + MediaPipe Pose, desktop only |
| Tests | 72 automated tests, including 7 real recorded workout sets |
| Builds | Windows: 311 MB folder. Android: 143 MB APK |

## Background

The original AWXCEND is a React web app that grew a lot of features over time. Our professor approved rebuilding its **first version** (the feature set from early September) in Python + Flet instead of porting everything. The web app is paused while this rebuild is in progress.

Decisions we made at the start:

- **Two platforms:** a Windows desktop app and an Android APK.
- **Simpler camera counting:**
  - The web app uses DTW: it compares every rep against a reference rep you record first.
  - The rebuild uses angle thresholds instead. It watches one joint angle and counts top, then bottom, then back to top. This is easier to explain, test and tune.
- **Keep all the first-version extras:** Gymunnity feed and chat, friends and direct messages, the AI coach, and the admin panel.
- **A backend of our own:** a new Supabase project owned by the group.
  - It was cloned from the web app's backend with **no user data copied**.

## Team

| Role | Responsibility | Supabase role |
|---|---|---|
| Leader / UI | App screens, design, camera testing | Administrator |
| Backend | Supabase project owner | Owner |
| Testing & docs | Testing, documentation | Developer |

## How we worked

- The team leader built the app with **Claude Code**, an AI coding assistant, as a pair programmer. Commits it helped write are marked "Co-Authored-By".
- **We planned first**, then built in phases, and each phase ended with something runnable.
- **We tested the logic that's easy to get wrong first:** the rep counters and the backend client.
- **We mutation-checked the tests:**
  - We broke the code on purpose and confirmed that a test failed.
  - This caught one test that was passing for the wrong reason.
- **Camera rule: never change a number without a recording.**
  - Every camera set saves the tracked joint positions to a CSV file. It saves numbers only, never video.
  - A replay tool runs that file back through the counter.
  - Each real set we fixed became a permanent test.

## Timeline

**Day 1: 26 September**

1. **Plan and camera spike.**
   - Before building 20 screens, we checked the riskiest part first: can Flet show live OpenCV camera frames smoothly?
   - Yes: 28 frames per second.
2. **Foundation.** Backend client, app shell, and login/signup/forgot-password.
3. **Backend clone** into the group's Supabase project.
4. **All the screens:**
   - dashboard, log workout, food log;
   - Gymunnity, friends and DMs;
   - profile, leaderboard, AI coach, admin.
5. **Camera workouts:**
   - push-up, squat, lunge and bicep curl;
   - using the phone as the camera;
   - seven rounds of tuning with real recorded sets (below).
6. **Packaging.** The Windows app, and the first Android APK attempts.
7. **First commit:** the complete app.

**Day 2: 27 September**

8. USDA food search went live, and we added a **Rotate video** option for sideways phone cameras.
9. **Design pass.** We restyled every screen into the "System window" look, because the first version looked "too plain and boring".
10. **Final builds.**
    - Build-script fixes.
    - Pushed to GitHub.
    - Fixed the APK carrying desktop-only files.

## Problems we hit and how we solved them

### Backend

**1. We couldn't rebuild the database from the web app's migration files.**
- **Cause:** the first ten migrations in the web repo are empty placeholders. Those changes had been applied through a tool and never saved as SQL.
- **Fix:**
  1. We dumped the live schema: structure only, no rows.
  2. Separately, we copied 19 reference tables: exercises, XP rules, foods, notices and similar.
  3. Before copying each table, we checked that it has no user columns.
- **Result:** no users, logs, posts or chats left the original project.

**2. The clone quietly made private database functions public.**
- **Cause:** a new Supabase project automatically lets anyone call new functions. The original project had removed that access in migrations that didn't come across in the dump.
  - So 87 functions that run with admin rights, plus a private view, were callable by anyone.
- **Fix:**
  - A migration that removes that access again.
  - We checked it with a fingerprint, a hash of every permission, which now matches the original project exactly.
  - Test calls that pose as an anonymous user are now refused.
- **Lesson:** when you copy a database, compare its permissions, not just its tables.

**3. The free plan can't customise password-reset emails.**
- **Cause:** custom email templates need a paid email (SMTP) setup.
- **Fix:** the app accepts the reset link from the default email. You paste it into the app, then set a new password there.

**4. `supabase config push` has no preview.**
- It applies the whole config file immediately.
- Our first push failed because of the email-template setting.
- We removed that setting, reviewed the full change, and pushed again.

### Camera rep counting

This took the longest.

**How the counter works:**
- Each exercise watches one joint angle, such as the elbow for a push-up or the knee for a squat.
- A rep counts when the angle goes from the top to the bottom and back to the top.
- A gap between the top and bottom lines stops jitter from counting twice.

Every fix below came from replaying a real recorded set. Each of those sets is now a test.

| What we reported | What the recording showed | What we changed |
|---|---|---|
| Squat counted 8 when we did 5 | We couldn't tell without data, so we built the session recorder first. The next recorded set (8 squats) counted exactly right, and it became our first real-data test. We never reproduced the original over-count. | Session recorder and replay tool |
| Push-up counted 7 of 10 | The bottom of our push-ups reached 100–119°, but the counter needed 100° | A separate "count line" at 120°. 100° now only marks a "good depth" rep |
| Push-up counted 5 of 10 | An earlier "correct" 10 had been right by accident: it counted lying down as a rep, and it merged two quick reps. Two later sets had only 6 and 5 push-ups visible to the camera at all | Top line 140°. A rep that takes longer than 6 s doesn't count |
| Push-up counted 4, then 3 | **Stream backlog.** The app processed frames slower than the phone sent them, fell seconds behind, and dropped whole chunks | A reader thread that keeps only the newest frame. A test streams numbered frames to a deliberately slow reader |
| Push-up counted 5 | The phone only sent 12–16 frames per second at 1080p, so the bottom of some reps never arrived | A live "resolution · fps" readout and a warning below 18 fps. The setup help now says to use 640×480 |
| Push-up counted 8, then 11 | At 2K the phone ran at 10.5 fps and counted 8. At 640×480 it ran at 25.8 fps and counted all 10, plus 1 from reaching for the phone afterwards | After 1 s out of position the counter pauses, and it needs a steady start before counting again |
| Bicep curl counted 0 of 10 | The phone was upright but streamed landscape, so the video arrived **sideways**. The anti-swing check compared the arm with the screen's vertical, and failed on every frame | Compare the upper arm with the **torso** instead, which works at any rotation. Later we added the Rotate video option |
| Lunge counted 9 of 10 | Lunges on the far leg look shallower from the side (96–122° instead of 64–73°) | Count line 135°, and a minimum lunge time of 0.8 s so weight shifts don't count |
| Lunge counted 8 and 12 | 8: when standing side-on, the far leg hides behind the near one, which paused the counter. 12: the steps between lunges dipped the knees | 8: one visible straight leg now means "standing". 12: the hips must drop at least 15% of leg length compared with a learned standing position |

**What we learned from the camera work:**
- **Record before you tune.** Guessing thresholds only moved the error around. Every real fix came from a recording.
- **Check the camera, not just the code.** Three of the problems were in the video itself: backlog, low fps and sideways video. No counting rule could have fixed those.
- **Measure the body against itself.** Any check against the screen's up and down breaks when the phone is rotated.
- **A correct count can be correct by accident.** One "perfect 10" was two mistakes cancelling out.

### Packaging

**Windows**

- **`flet build windows` needs Visual Studio,** which we don't have. We used `flet pack`, which uses PyInstaller, through `tools/build_windows.py`.
- **Collecting all of MediaPipe also pulled in PyTorch.** We collect only MediaPipe's binaries and data files.
- **Excluding matplotlib to save space broke the camera,** because MediaPipe loads it at startup.
  - The build succeeded anyway. Only the packaged self-check (`AWXCEND.exe --selfcheck`) caught it.
  - **Lesson:** a build that finishes isn't a build that works. Test the packaged app.
- **`flet pack` deletes the `build` folder, which deleted a finished APK.** The Windows build now runs from its own folder and writes to `dist/windows`.

**Android**

- **Windows Developer Mode is required,** because the Flutter build needs symbolic links.
- **Flet's installer didn't accept the Android SDK licences on Windows,** so the SDK packages never installed. We installed them manually with `sdkmanager`.
- **The APK shipped desktop-only camera files.**
  - Flet's packager only skips a path that matches exactly, and on Windows it writes paths with backslashes (`pose\camera.py`). Our list used forward slashes, so nothing was skipped.
  - We now list each path both ways, and the APK went from 148 to 143 MB.
  - **Lesson:** open the package and look inside it.
- **There's no camera tracking on Android:** MediaPipe for Python has no Android build. The phone app shows everything else.

### Flet quirks (version 0.86)

- **Colours with transparency are written `#AARRGGBB`,** alpha first. Adding "33" to the end of a blue turned it green. We use a `fade()` helper instead.
- **`ink` (click ripple) and `animate` on the same container apply its padding twice,** which made clickable cards too tall. We never combine them.
- **Text fields are 300 px wide by default,** so they stopped short of the card on desktop. Form columns now stretch their children.
- **A row set to wrap shrinks to its content** instead of filling the card.
- **Shared preferences, the file picker and route changes are async** in this Flet version.

### Design

The first version worked but looked "too plain and boring".

- **One shared kit.** We moved the whole look into `src/ui.py`:
  - the background auras;
  - glass panels with glowing edges and corner brackets;
  - Michroma titles, section headers, and a segmented XP bar;
  - glowing buttons and lit tabs.
- **Screens only use the kit,** so one change restyles the whole app.
- **Screenshot review.** We checked every screen at phone width (390 px) and desktop width (1280 px) and fixed what they showed:
  - cards that were too tall;
  - clipped labels;
  - short text fields;
  - a card nested inside another card.

### GitHub

- The first push was refused (403) until the leader was added as a collaborator on the group repository.
- **Before every push we scan for secrets.**
  - The only key in the repo is Supabase's *publishable* key, which is safe to share because Row Level Security protects the data.
  - The service key, the API keys and the `.env` files never enter the repo.

## What we'd do again, and what we'd do differently

**Again:**
- record real data before tuning;
- test the packaged app, not just the code;
- keep secrets out of the repo from the first commit;
- build the riskiest part (the camera) first.

**Differently:**
- record camera sets from the very first test;
- check the phone camera settings (640×480, orientation) before testing any counter;
- ask for repository access before the day we need to push.

## Known limitations (as of 27 September 2026)

- **Camera tracking is desktop-only.**
- **Camera sets are saved as manual logs** after you confirm the count, because the server only gives camera XP to exercises that have passed its validation.
- **The AI coach needs the leader's Ollama server running,** reachable through a tunnel.
- **Food search uses the USDA demo key,** which is rate-limited. A free personal key raises the limit.
- **Password reset works by pasting the emailed link** into the app.
- **The APK hasn't been tested on a real phone yet.**
