"""Train tab: Log Workout form, the XP result dialog, and the way into camera workouts."""
import flet as ft

import ui
from api import ApiError

# Must agree with public.exercises (name + metric_type) or log-workout rejects the save.
EXERCISES = [
    ("atlasstone", "Atlas Stone"), ("barbellbicepscurl", "Barbell Bicep Curl"), ("benchpress", "Bench Press"),
    ("burpee", "Burpee"), ("cleanandjerk", "Clean & Jerk"), ("chestflymachine", "Chest Fly Machine"),
    ("cycling", "Cycling"), ("deadlift", "Deadlift"), ("declinebenchpress", "Decline Bench Press"),
    ("farmerscarry", "Farmer's Carry"), ("hammercurl", "Hammer Curl"), ("hipthrust", "Hip Thrust"),
    ("inclinebenchpress", "Incline Bench Press"), ("latpulldown", "Lat Pulldown"), ("lateralraise", "Lateral Raise"),
    ("legextension", "Leg Extension"), ("legraises", "Leg Raises"), ("lunges", "Lunges"),
    ("mountainclimbers", "Mountain Climbers"), ("plank", "Plank"), ("powerclean", "Power Clean"),
    ("pullup", "Pull Up"), ("pushup", "Push Up"), ("romaniandeadlift", "Romanian Deadlift"),
    ("russiantwist", "Russian Twist"), ("shadowboxing", "Shadow Boxing"), ("shoulderpress", "Shoulder Press"),
    ("sideplank", "Side Plank"), ("snatch", "Snatch"), ("squat", "Squat"), ("tbarrow", "T-Bar Row"),
    ("tricepdips", "Tricep Dips"), ("triceppushdown", "Tricep Pushdown"), ("wallsit", "Wall Sit"),
    ("yokewalk", "Yoke Walk"),
]
TIMED = {"cycling", "plank", "shadowboxing", "sideplank", "wallsit"}
LBS_PER_KG = 2.20462


def show_result(app, res: dict) -> None:
    """XP earned + rank/level news after a save, then refresh the profile in the background."""
    lines = [ft.Row([ft.Icon(ft.Icons.BOLT, color=ui.C.primary_bright, size=32),
                     ui.num(f"+{res.get('xp_earned', 0)} XP", 30, ui.C.primary_bright)],
                    alignment=ft.MainAxisAlignment.CENTER)]
    if res.get("previous_rank") and res.get("current_rank") != res.get("previous_rank"):
        lines.append(ui.heading(f"Rank up! {res['previous_rank']} → {res['current_rank']}", 16, ui.C.gold))
    elif res.get("sub_rank_changed"):
        lines.append(ui.heading(f"Now {res.get('current_rank')} {res.get('rank_sub_index') or ''}", 15, ui.C.accent))
    if res.get("level_up_triggered"):
        lines.append(ui.heading("Level up!", 16, ui.C.accent))
    if res.get("next_rank") and res.get("xp_to_next_rank"):
        lines.append(ui.body(f"{res['xp_to_next_rank']:,} XP to {res['next_rank']}"))
    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text("Workout logged"),
        content=ft.Column(lines, tight=True, spacing=10, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        actions=[ui.button("Nice", lambda e: app.close_dialog())]))

    def refresh():
        try:
            app.load_me()
        except ApiError:
            pass
    app.run(refresh)


def log_workout(app, payload: dict, on_done=None) -> None:
    """Save locally first, then let the durable sync queue try the server."""
    def work():
        """ 
        The real screen is only reachable after authentication.  Keeping the
        old direct path for lightweight view fakes (which intentionally omit
        a session) preserves the existing online-screen tests and behavior.
        """
        if not app.api.user_id:
            try:
                res = app.api.call("log-workout", "POST", {**payload, "workout_source": "manual"})
            except ApiError as ex:
                app.toast(str(ex), error=True)
                if on_done:
                    on_done(False)
                return
            show_result(app, res)
            if on_done:
                on_done(True)
            return
        try:
            local = app.store.add_workout({**payload, "workout_source": "manual"})
        except Exception as ex:
            app.toast(f"Could not save this workout locally: {ex}", error=True)
            if on_done:
                on_done(False)
            return

        result = app.sync_pending()
        current = next((w for w in app.store.list_workouts() if w.get("local_id") == local["local_id"]), local)
        if current.get("sync_status") != "synced":
            message = "Workout saved on this device. It will sync when the connection returns."
            if current.get("sync_error"):
                message += f" ({current['sync_error']})"
            app.toast(message, error=False)
            if on_done:
                on_done(True)
            return
        try:
            show_result(app, current)
        except ApiError as ex:
            app.toast(str(ex), error=True)
        if on_done:
            on_done(True)
    app.run(work)


def open_camera(app) -> None:
    if not app.is_desktop:
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text("Camera workouts"),
            content=ft.Text("Camera rep counting runs on the AWXCEND desktop app. On your phone, use Log workout."),
            actions=[ui.button("OK", lambda e: app.close_dialog(), kind="text")]))
        return
    try:
        from views import camera  # desktop only: pulls in OpenCV + MediaPipe
    except ImportError:
        app.toast("Camera tracking isn't installed in this build (needs opencv-python and mediapipe).", error=True)
        return
    app.open(camera.view)


def view(app) -> ft.Control:
    state = {"unit": "kg"}
    exercise = ui.dropdown("Exercise", EXERCISES, "benchpress", enable_filter=True, editable=True, expand=True)
    sets = ui.number_field("Sets", 3, expand=True)
    reps = ui.number_field("Reps", 10, expand=True)
    weight = ui.number_field("Weight (kg)", "", decimals=True, expand=True)
    minutes = ui.number_field("Minutes", 10, expand=True)
    seconds = ui.number_field("Seconds", 0, expand=True)
    rep_inputs = ft.Column([ft.Row([sets, reps], spacing=10), ft.Row([weight], spacing=10)], spacing=10)
    time_inputs = ft.Row([minutes, seconds], spacing=10, visible=False)

    def set_unit(u):
        state["unit"] = u
        weight.label = f"Weight ({u})"
        weight.update()

    def on_exercise(e=None):
        timed = exercise.value in TIMED
        rep_inputs.visible, time_inputs.visible = not timed, timed
        app.page.update()

    exercise.on_select = on_exercise

    def submit(e):
        ex = exercise.value
        if ex not in dict(EXERCISES):
            app.toast("Pick an exercise from the list.", error=True)
            return
        if ex in TIMED:
            total = int(minutes.value or 0) * 60 + int(seconds.value or 0)
            if not 1 <= total <= 21600:
                app.toast("Duration must be between 1 second and 6 hours.", error=True)
                return
            payload = {"exercise": ex, "duration_seconds": total}
        else:
            s, r = int(sets.value or 0), int(reps.value or 0)
            if not (1 <= s <= 20 and 1 <= r <= 300):
                app.toast("Sets must be 1-20 and reps 1-300.", error=True)
                return
            w = float(weight.value) if weight.value else None
            if w is not None and state["unit"] == "lbs":
                w = round(w / LBS_PER_KG, 2)
            if w is not None and not 0 <= w <= 500:
                app.toast("Weight must be 0-500 kg.", error=True)
                return
            payload = {"exercise": ex, "sets": s, "reps": r, "weight_kg": w}
        save.disabled = True
        app.page.update()

        def done(ok):
            save.disabled = False
            app.page.update()
        log_workout(app, payload, done)

    save = ui.button("Log workout", submit, icon=ft.Icons.CHECK, height=48, width=float("inf"))
    form = ui.card(ft.Column([
        exercise,
        ft.Row([ui.label("Weight unit"), ui.chips([("kg", "kg"), ("lbs", "lbs")], "kg", set_unit)], spacing=12),
        rep_inputs, time_inputs, save,
    ], spacing=14), padding=18)

    camera = ui.card(ft.Row([
        ft.Icon(ft.Icons.CAMERA_ALT_OUTLINED, color=ui.C.camera, size=30),
        ft.Column([ui.heading("Camera workout", 15), ui.body("Push-ups, squats, lunges and curls counted by your webcam.", size=13)],
                  spacing=2, expand=True),
        ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim),
    ], spacing=14), on_click=lambda e: open_camera(app), accent=ui.fade(ui.C.camera, 0x66))

    from views import game, plan, routines, run  # local: these import this module

    def entry(title, text, icon, color, screen):
        return ui.card(ft.Row([
            ft.Icon(icon, color=color, size=30),
            ft.Column([ui.heading(title, 15), ui.body(text, size=13)], spacing=2, expand=True),
            ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim),
        ], spacing=14), on_click=lambda e: app.open(screen), accent=ui.fade(color, 0x66))

    more = [
        entry("Run or walk", "Track distance with your phone's GPS. Only the total is saved, never your route.",
              ft.Icons.DIRECTIONS_RUN, ui.C.primary_bright, run.view),
        entry("Missions", "Boss fights you clear with your sets. Rewards XP, gold and collectibles.",
              ft.Icons.FLAG, ui.C.gold, lambda a: ui.screen("Missions", game.missions(a))),
        entry("Training plan", "A month of sessions made for your goal, days and equipment.",
              ft.Icons.CALENDAR_MONTH, ui.C.food, plan.training),
        entry("My routines", "Save the workouts you repeat and log them in a few taps.",
              ft.Icons.LIST_ALT, ui.C.accent, routines.view),
        entry("Dungeons", "Party boss events and who closed the most gates.", ft.Icons.CASTLE, ui.C.danger, game.dungeons),
    ]

    return ui.screen("Train", camera, ui.section("Log a workout"), form, ui.section("More training"), *more,
                     subtitle="Every set you log earns XP toward your rank.")
