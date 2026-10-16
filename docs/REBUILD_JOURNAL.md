# AWXCEND rebuild journal: Python + Flet

This is a record of how we rebuilt AWXCEND in Python and Flet between 26 and 27 September 2026, and how we fixed and extended it after the first release (16 October 2026). It covers the problems we ran into, how we solved them, and what we learned. To run or build the app, see the [README](../README.md).

## At a glance

| | |
|---|---|
| What | The first version of AWXCEND, a gamified fitness tracker, rebuilt in Python |
| UI framework | [Flet](https://flet.dev) 0.86 (Python on top of Flutter) |
| Platforms | Windows desktop app, and an Android APK |
| Backend | Our own Supabase project: Postgres with Row Level Security, Auth, and 64 Edge Functions |
| Camera | OpenCV + MediaPipe Pose, desktop only |
| Tests | 121 app tests (including 7 real recorded workout sets) and 7 server-rule tests, run by GitHub Actions on every push |
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
11. **Release and phone test.**
    - Published v1.0.0 on GitHub with the Windows and Android downloads.
    - Connected the AI coach.
    - Tested the APK on a real phone: every feature worked as intended.

**After release: 16 October**

12. **Bug sweep.** A full review of the app found the forgot-password failure, lost logins when offline, duplicate saves, wrong times, and phone layouts that broke. All fixed and released as a commit.
13. **Features the web app had and we didn't:**
    - roles in the admin panel (moderator and admin sections);
    - moderation sanctions: ban an account, or restrict posting, chat, DMs, friend requests or reporting, for a set time or permanently;
    - account and privacy: download your data, hide or delete your account, report a problem;
    - routines, the monthly training plan, missions, the shop, the collection and the Dungeon board;
    - deleting a workout logged by mistake, and deleting a meal.
14. **Acceptance check.** We audited the app the way a professor would check it. It scored 72/100, "launchable with caveats", and listed what to fix next.
15. **Hardening.**
    - Custom email (Brevo SMTP) so password resets reach everyone.
    - Automatic tests on GitHub.
    - Limits on hidden characters and on chat message length.
    - A security review.

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

**5. The AI coach showed "offline" even with Ollama running.**
- **Cause:** the app never talks to Ollama directly.
  - It asks our Supabase server, which reaches Ollama through an ngrok tunnel.
  - That tunnel is protected by a rule that rejects requests without a secret key.
  - The new project was missing `OLLAMA_URL` and `OLLAMA_SECRET`: they were set on the web project but never on the new one. So the server looked for Ollama inside Supabase's own cloud, and the tunnel received zero requests.
- **Fix:** we set both secrets on the new project. No redeploy was needed.
- **Lesson:** when you clone a backend, list the old project's secrets and set every one on the new project, not just the database.

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
- **There's no camera tracking on Android.** See the next section for why. The phone app hides the camera screen and shows everything else.

### Why camera tracking only works on desktop

This was a deliberate decision at the start of the project, not a missing feature. There are three reasons:

1. **The pose-detection library has no Android version for Python.**
   - Camera counting uses Google's MediaPipe to find your joints in each video frame.
   - MediaPipe publishes ready-made versions of its Python package only for Windows, Mac and Linux.
   - Flet runs our Python code on the phone, but it can only use libraries that have an Android version. On a phone the camera code can't even load.
2. **Flet can't stream the phone's live camera into Python.**
   - Flet 0.86 has no camera widget that hands video frames to our code.
   - On desktop we read the webcam with OpenCV, which has the same Android problem.
3. **Speed.**
   - Even if both worked, pose detection in Python on a phone would likely be too slow.
   - Our counts already went wrong whenever the video dropped below about 18 frames per second.

**What to do instead:** use the phone *as the camera* for the desktop app.
- The phone films you over Wi-Fi with the IP Webcam app, set to 640×480.
- The laptop does the counting.
- Every real set we tested used this setup.

**Ways to get camera counting on Android later.** Each would be a project of its own:
- **A native Android part.** MediaPipe has an official Android library, just not for Python. We would write a custom Flet extension in Dart or Kotlin that uses it.
- **The original web app.** It runs MediaPipe in the browser, so its camera works on phones.

### Flet quirks (version 0.86)

- **Colours with transparency are written `#AARRGGBB`,** alpha first. Adding "33" to the end of a blue turned it green. We use a `fade()` helper instead.
- **`ink` (click ripple) and `animate` on the same container apply its padding twice,** which made clickable cards too tall. We never combine them.
- **Text fields are 300 px wide by default,** so they stopped short of the card on desktop. Form columns now stretch their children.
- **A row set to wrap shrinks to its content** instead of filling the card.
- **Shared preferences, the file picker and route changes are async** in this Flet version.
- **A toast (SnackBar) counts as a dialog.** `page.pop_dialog()` closed the toast instead of the dialog under it. `App.close_dialog()` skips toasts.
- **An input filter that allows a pattern refuses the whole keystroke** when the result wouldn't match, and keeps the old text. A filter that *denies* a pattern removes only the matching characters. We use the first kind for numbers and the second for hidden characters.

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

### After release (16 October)

**1. Forgot password sent no email to most people.**
- **Cause:** Supabase's built-in email only delivers to members of the Supabase organisation, and only 2 emails an hour for the whole project. Everyone else got nothing. The app also misread some errors, because Supabase Auth names the error in `error_code` on some replies and `code` on others.
- **Fix:**
  - Custom SMTP through Brevo, set up by the project owner. The SMTP key lives only in the Supabase dashboard, never in the repo.
  - A higher email limit.
  - In the app: clear messages for "email not allowed", "too many emails", "link expired" and "account suspended". The pasted link is decoded properly, the new password must be typed twice, and Enter submits.
- **Lesson:** a feature that works for the team can still fail for everyone else. Test with an account that isn't one of ours.

**2. The app logged you out whenever you opened it offline.**
- **Cause:** a failed token refresh was treated as "session expired", even when the real reason was no internet.
- **Fix:** the saved login is kept when the server can't be reached, and the app says why it couldn't connect.

**3. Small bugs from a full review:**
- **Double saves.** Tapping Save twice quickly logged two workouts. Buttons now lock while saving.
- **Wrong times.** Some database columns store UTC without saying so, so "2 hours ago" showed in the wrong time zone. Times without a zone are now read as UTC.
- **A lone "." in a number box crashed the form.** The decimal pattern now refuses it but still allows ".5".
- **Phone layouts.** Four food totals in one row broke numbers in half at 360 px, so they now sit in a 2 × 2 grid.

**4. Bans had to stop a player straight away, not after their login expired.**
- **Cause:** a signed-in player's access token stays valid for up to an hour.
- **Fix:**
  - The sanctions function sets an Auth ban, so the player can't sign in or refresh.
  - Every Edge Function also checks for an active ban on each request, so it takes effect at once.
  - The player sees the reason and the end date.
  - Export, delete account and privacy choices still work while banned: a sanction limits the game, never someone's rights over their own data.
- **Rules:**
  - moderators can't sanction admins or each other;
  - only an admin can lift a sanction an admin issued;
  - nobody can lift their own;
  - every action goes in the audit log.
  - These rules are pure functions with their own tests.

**5. Deleting a workout had to take back exactly what it gave.**
- **Cause:** a workout changes total XP, path XP and rank, attribute points and personal records. Undoing it in several steps could leave half of them changed if something failed in the middle.
- **Fix:**
  - One database function does it all in a single transaction, the same way logging a workout does.
  - It only allows hand-logged workouts from the last 24 hours that weren't part of a mission or dungeon and come from your current path. That way deleting can't be used to farm rewards.

**6. `supabase db push` said "Remote migration versions not found", and deploy said "No Functions found".**
- **Cause:** both commands were run from the `src` folder. The Supabase CLI looks for a `supabase` folder in the current folder, so it saw no migrations and no functions.
- **Fix:** run them from `backend`.

**7. Hidden characters and endless messages.**
- **Cause:** text boxes accepted:
  - zero-width spaces, which can make two names look the same;
  - text-direction overrides, which make "gnp.exe" display as "exe.png";
  - control codes;
  - "zalgo" text with piles of stacked accent marks that draw over other messages.
- **Fix:**
  - We first blocked them in every text box too, but that filter stopped ALL typing in the real app (the pattern didn't survive the trip from Python to Flutter), while our tests passed. We removed it: only the server cleans text now. **Lesson:** a test that checks a setting was applied doesn't prove the app still works; type in the real app.
  - The server removes them again and cuts accent stacks to two, because the app is not the only way to call the server.
  - Chat and DM messages are limited to 100 words.
  - Emoji and accented letters still work.

**8. Security review.** We went through every Edge Function and the database permissions:
- **Already good:**
  - every function checks the login;
  - admin actions check the role on the server;
  - every table has Row Level Security;
  - the only key in the app is the publishable one;
  - nothing secret is in the Git history;
  - update-profile accepts only the fields it lists;
  - uploads check the file type, size and path.
- **Fixed:**
  - **Direct database writes.** Routines and camera templates could be written straight through the database API with the public key. That skipped the length limits and rate limits, so it was an easy way to fill the database. A migration now removes that access. The app always went through the Edge Functions anyway.
  - **Ban check gaps.** Four moderator functions had their own copy of the login check, without the ban check. A banned moderator could have kept handling reports for up to an hour. They now use the shared check.
  - **Build zip.** A build zip could have been committed by accident, so `*.zip` is now ignored.
- **Accepted for now:**
  - **The rate limiter "fails open".** If the counter table is unreachable, requests are allowed rather than blocking the whole app.
  - **Some error messages pass on database wording.** That can reveal table names but no data.
  - **Rate limits only on actions that write or cost money.** Reading screens aren't rate-limited.
- **Load:**
  - Edge Functions scale automatically, and they talk to the database over HTTP, so there are no connection pools or load balancers for us to run.
  - The main load is chat polling: one request every 5 seconds per open chat screen.
  - Supabase Realtime would replace polling if the app grew past a few hundred people chatting at once.

**9. Legal documents described the wrong app.**
- **Cause:** the privacy notice we cloned described the web app: GPS runs, and downloads from Google and jsDelivr. There were no Terms of Use, no age limit, and no cookie policy.
- **Fix:**
  - **Three documents written for this app,** under Philippine law: Terms of Use, a Privacy Policy and a Cookie and Local Storage Policy.
    - The Privacy Policy follows the Data Privacy Act of 2012 (RA 10173).
    - The Terms cover health and safety, community rules (Safe Spaces Act, cyber libel), fair play, game items with no money value, "as is" service and governing law.
    - The cookie policy says the app sets no cookies, and lists what it stores on the device.
  - **Versioned on the server,** like the old notice, so a new version reaches every app without a rebuild.
  - **Adults only.** Sign-up needs an age of 18 or over and acceptance of the Terms and Privacy Policy, and the server records both. Profile edits can't set an age under 18 either.
  - **Updated versions must be accepted.** When a document changes, signed-in players are asked to accept it, or they can sign out.
- **Note:** these are written in-house, not by a lawyer. Have them reviewed before any real public launch.

**10. Mistakes couldn't be fixed (the gap to a 90+ score).**
- **Chat and DMs:** you can now edit your own message for 15 minutes and delete it any time (a DM disappears for both people). Edits follow the same rules as sending: 100 words, hidden characters stripped, and a muted player can't edit. An "edited" tag shows on the message.
- **Meals:** change the amount, and calories and macros scale in proportion.
- **Workouts:** correct sets, reps, weight or time.
  - **Problem:** XP, rank, attribute points and the strength record all depend on those numbers, so patching the row would leave them wrong.
  - **Fix:** an edit is "take the old workout back, log the new one", inside one database transaction, so a failure rolls back both halves. The original time is kept, so editing doesn't extend the 24-hour window. The same limits as deleting apply.
- **Left out on purpose:** changing the exercise itself (delete and log again), and moderators deleting other people's chat messages.

## What works where, and why

### How one Python app runs on both Windows and Android

- **Flet draws every screen with Flutter,** Google's UI toolkit. That's why the same screens look the same on a laptop and a phone.
- **On Windows,** the build (PyInstaller, via `flet pack`) packs a whole Python interpreter into the `AWXCEND` folder. It also packs our code, OpenCV, and MediaPipe's compiled libraries. Nothing needs to be installed on the PC.
- **On Android,** the APK carries its own small Python interpreter and runs our code inside the app.
- **All the data goes over the internet to our Supabase backend,** through `httpx`.
  - `httpx` is written in plain Python, so it runs anywhere Python runs.
  - The server decides XP, ranks, permissions and validation, so both apps behave the same.

### Feature by feature

| Feature | Windows | Android | Why |
|---|---|---|---|
| Sign up, log in, stay logged in | Yes | Yes | Plain web requests. The login is saved with Flet's shared preferences on both platforms |
| Reset password | Yes | Yes | Paste the link from the email. On a phone, long-press the link, copy it, and paste it into the app |
| Dashboard, XP, levels, ranks | Yes | Yes | Calculated by the server and shown by the app |
| Log a workout | Yes | Yes | Plain web requests |
| Camera rep counting | Yes | **No** | Needs MediaPipe and OpenCV, which have no Android build for Python (see "Why camera tracking only works on desktop") |
| Phone as the camera | Yes | No | The phone films and the laptop counts. It's part of the desktop camera feature |
| Food search and meal log | Yes | Yes | USDA and our food table, through the server |
| Gymunnity feed and chat, friends, DMs | Yes | Yes | Plain web requests. New messages are fetched every 5 s in chat and every 4 s in DMs, only while that screen is open |
| **Posting a photo** | Any photo | **Only a JPEG under 2 MB** | The server accepts JPEGs up to about 2 MB. On desktop the app shrinks and converts photos with OpenCV. OpenCV isn't in the phone app, so it can only send a photo that's already small enough. Photos from a phone camera are often bigger |
| Leaderboard, profiles | Yes | Yes | Plain web requests |
| AI coach | Yes* | Yes* | *Only while the leader's Ollama AI server and tunnel are running |
| Admin panel | Yes | Yes | Checked by the server for every action |
| Macs and Linux | Untested | — | The code allows the camera on any desktop, but a Mac or Linux build has to be made on that system, and we only have Windows |
| iPhone | — | Not built | Building for iPhone needs a Mac with Xcode |

### Limits of Python + Flet that we ran into

1. **Libraries with compiled code need a separate build for each platform.**
   - Plain-Python libraries such as `httpx` work everywhere.
   - MediaPipe and OpenCV are mostly C++. Their Python packages come ready-made for Windows, Mac and Linux, but not for Python on Android.
   - Because of that, camera counting and photo resizing only exist on desktop.
2. **No live camera stream into Python.** Flet 0.86 has no camera widget that hands video frames to our code. On desktop we read the webcam with OpenCV instead.
3. **Big apps.**
   - Each app carries a whole Python interpreter plus Flutter's engine.
   - The APK is 143 MB. The Windows folder is 311 MB, mostly because of MediaPipe and OpenCV.
   - A web app is far smaller, because the browser already has everything.
4. **Building needs a heavy setup.**
   - Flet's own Windows build needs Visual Studio, so we used PyInstaller instead.
   - The Android build needs Windows Developer Mode and several GB of downloads (Flutter, Java, the Android SDK), and we had to install the SDK by hand.
   - Mac and iPhone builds need a Mac.
5. **The Windows app isn't code-signed,** so Windows SmartScreen shows a warning the first time it runs. The fix is **More info → Run anyway**.
6. **Anything inside the app can be read by someone who unpacks it.**
   - That's why the app only contains the *publishable* Supabase key.
   - Every rule is enforced on the server, never trusted to the app.
7. **No push notifications, and no offline mode.**
   - Messages only arrive while the chat screen is open.
   - The app needs the internet for almost everything.
8. **Flet is young and changes fast.**
   - Version 0.86 changed many names from older tutorials. Some examples we found online didn't match.
   - It also has the quirks listed above. We pinned `flet==0.86.5` so an update can't break the build.

### Limits that come from our services, not from Flet

- **Supabase's free plan:**
  - its built-in email only reaches members of the Supabase organisation, 2 an hour. We send through Brevo's SMTP instead (300 emails a day on Brevo's free plan);
  - it **pauses a project after about a week with no activity.** Open the Supabase dashboard and restore it before a demo if it's been quiet.
- **The USDA demo key is rate-limited.** A free personal key from api.data.gov raises the limit.
- **The AI coach runs on the leader's own PC** through Ollama and a tunnel. When that PC is off, the AI coach is unavailable.
- **Camera sets are saved as manual logs** after you confirm the count. The server only gives camera XP to exercises that have passed its validation, and our Python counters haven't been through that process.

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

## Known limitations (as of 16 October 2026)

The full reasons are in "What works where, and why" above.

- **Camera tracking is desktop-only.** Use the phone as the camera for the desktop app.
- **The phone app can only post photos that are already JPEGs under 2 MB.**
- **Camera sets are saved as manual logs** after you confirm the count.
- **The AI coach only works while the leader's Ollama server and tunnel are running.**
- **Food search uses the USDA demo key,** which is rate-limited.
- **Password reset works by pasting the emailed link** into the app.
- **There are no push notifications and no offline mode.** Chat updates every few seconds while it's open.
- **The Supabase project pauses after about a week of inactivity** (free plan). Restore it before a demo.
- **The Windows app isn't code-signed,** so SmartScreen warns on the first run.
- **Only the Windows and Android builds exist.** Mac, Linux and iPhone builds have to be made on those systems.
- **Dungeon fights, food photo scan, coach verification and the admin food and dungeon editors** exist on the server but have no screen in this app yet.
