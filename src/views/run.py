"""Run or walk with GPS: live distance and time, then one workout is logged (log-workout, distance + time).
The route itself is never stored or sent: only the total distance and time leave the device.
Foreground only: the screen is kept awake while a run is active, and leaving the screen ends it."""
import asyncio
import time

import flet as ft

import gps
import ui
from api import ApiError
from views import train

try:
    import flet_geolocator as fg
except ImportError:  # not in this build
    fg = None

ACTIVITIES = [("walking", "Walking"), ("jogging", "Jogging"), ("rucking", "Rucking")]
MIN_LOG_M = 100  # shorter than this isn't worth a workout (and is mostly GPS settling)


def clock(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"


def pace(distance_m: float, seconds: float) -> str:
    """Minutes per kilometre, '–' until there is enough distance for it to mean something."""
    if distance_m < 50 or seconds < 1:
        return "–"
    s = seconds / (distance_m / 1000)
    return f"{int(s // 60)}:{int(s % 60):02d}/km"


def ensure_consent(app, proceed, cancel) -> None:
    """The one-time 'Before your first run or walk' notice (stored like every other consent).
    Calls proceed() once it is accepted, or cancel() if it can't be or isn't."""
    def work():
        try:
            status = app.api.call("privacy")
        except ApiError as ex:
            app.toast(str(ex), error=True)
            cancel()
            return
        notice = (status.get("notices") or {}).get("gps")
        if not notice or (status.get("latest") or {}).get("gps", {}).get("is_current"):
            proceed()  # accepted already (or no notice published: nothing to ask)
            return

        def accept(e):
            app.close_dialog()

            def record():
                try:
                    app.api.call("privacy", "POST", {"action": "acknowledge", "consent_type": "gps",
                                                     "notice_version": notice["version"]})
                except ApiError as ex:
                    app.toast(str(ex), error=True)
                    cancel()
                    return
                proceed()
            app.run(record)
        app.page.show_dialog(ft.AlertDialog(
            modal=True, title=ft.Text(notice["title"]), scrollable=True,
            content=ft.Container(ft.Markdown(notice["body"]), width=480),
            actions=[ui.button("Not now", lambda e: (app.close_dialog(), cancel()), kind="text"),
                     ui.button("I agree", accept)]))
    app.run(work)


def view(app) -> ft.Control:
    if fg is None or app.page.web:
        return ui.screen("Run / Walk", ui.empty("GPS tracking isn't available in this version of the app.",
                                                ft.Icons.LOCATION_OFF))
    page = app.page
    state = {"mode": "idle", "activity": "walking", "elapsed": 0.0, "mark": 0.0, "signal": None, "left": False}
    track = gps.Track()
    services: list = []

    distance_text = ui.num("0.00 km", 44, ui.C.primary_bright)
    time_text = ui.num("0:00", 28)
    pace_text = ui.num("–", 28)
    signal_text = ui.body("Press Start to begin.", size=13)
    hint = ui.body("", color=ui.C.gold, size=13)
    buttons = ft.Row(wrap=True, spacing=10, run_spacing=10)

    def elapsed() -> float:
        return state["elapsed"] + (time.monotonic() - state["mark"] if state["mode"] == "running" else 0.0)

    def render():
        d, secs = track.distance_m, elapsed()
        distance_text.value = f"{d / 1000:.2f} km"
        time_text.value = clock(secs)
        pace_text.value = pace(d, secs)
        acc = state["signal"]
        if state["mode"] == "idle":
            signal_text.value = "Press Start to begin."
        elif state["mode"] == "starting":
            signal_text.value = "Starting..."
        elif acc is None:
            signal_text.value = "Searching for GPS..."
        elif acc > gps.MAX_ACCURACY_M:
            signal_text.value = f"GPS too weak to count ({acc:.0f} m off)"
        else:
            signal_text.value = f"GPS good ({acc:.0f} m)"
        hint.value = ("This device's location is too rough to measure a run. Use your phone, outdoors."
                      if acc is not None and acc > 100 else
                      "Keep this screen open: leaving it ends the run." if state["mode"] != "idle" else "")
        buttons.controls = {
            "starting": [],
            "idle": [ui.button("Start", start, icon=ft.Icons.PLAY_ARROW)],
            "running": [ui.button("Pause", pause, icon=ft.Icons.PAUSE, kind="ghost"),
                        ui.button("Finish", finish, icon=ft.Icons.STOP, kind="accent")],
            "paused": [ui.button("Resume", resume, icon=ft.Icons.PLAY_ARROW),
                       ui.button("Finish", finish, icon=ft.Icons.STOP, kind="accent")],
        }[state["mode"]]

    def refresh():
        if state["left"]:
            return
        render()
        try:
            page.update()
        except Exception:  # screen already left
            state["left"] = True

    def on_position(e):
        if state["mode"] != "running":  # also covers readings still in flight after Pause or Finish
            return
        p = e.position
        t = p.timestamp.timestamp() if p.timestamp else time.time()
        track.add(p.latitude, p.longitude, p.accuracy, t)
        state["signal"] = p.accuracy
        refresh()

    async def tick():
        while state["mode"] == "running" and not state["left"]:
            refresh()
            await asyncio.sleep(1)

    def add_services(*items):
        for s in items:
            services.append(s)
            page.services.append(s)
        page.update()

    def drop_services():
        for s in services:
            try:
                page.services.remove(s)
            except ValueError:
                pass
        services.clear()

    async def begin():
        """Permission first, then the live position stream."""
        perm = fg.Geolocator()
        add_services(perm)
        if not await perm.is_location_service_enabled():
            app.toast("Turn on Location in your device settings.", error=True)
            await perm.open_location_settings()
            reset()
            return
        status = await perm.request_permission()
        if status in (fg.GeolocatorPermissionStatus.DENIED, fg.GeolocatorPermissionStatus.DENIED_FOREVER):
            app.toast("Location permission is needed to measure distance.", error=True)
            if status == fg.GeolocatorPermissionStatus.DENIED_FOREVER:
                await perm.open_app_settings()
            reset()
            return
        config = (fg.GeolocatorAndroidConfiguration(accuracy=fg.GeolocatorPositionAccuracy.BEST, distance_filter=0,
                                                    interval_duration=ft.Duration(seconds=2))
                  if page.platform == ft.PagePlatform.ANDROID else
                  fg.GeolocatorConfiguration(accuracy=fg.GeolocatorPositionAccuracy.BEST, distance_filter=0))
        add_services(fg.Geolocator(configuration=config, on_position_change=on_position),
                     ft.Wakelock())  # keep the screen awake: tracking only works in the foreground
        try:
            await services[-1].enable()
        except Exception:  # a screen that may sleep is a nuisance, not a failure
            pass
        state.update(mode="running", mark=time.monotonic(), signal=None)
        refresh()
        page.run_task(tick)

    def start(e=None):
        if state["mode"] != "idle":  # a second tap while the first is still getting permission
            return
        track.distance_m, state["elapsed"] = 0.0, 0.0
        track.break_here()
        state["mode"] = "starting"
        refresh()
        ensure_consent(app, lambda: page.run_task(begin), reset)

    def pause(e=None):
        state["elapsed"] += time.monotonic() - state["mark"]
        state["mode"] = "paused"
        refresh()

    def resume(e=None):
        track.break_here()  # the next reading starts a new stretch
        state.update(mode="running", mark=time.monotonic())
        refresh()
        page.run_task(tick)

    def reset():
        state.update(mode="idle", elapsed=0.0, signal=None)
        track.distance_m = 0.0
        track.break_here()
        drop_services()
        refresh()

    def finish(e=None):
        if state["mode"] == "running":
            pause()
        d, secs = track.distance_m, state["elapsed"]
        name = dict(ACTIVITIES)[state["activity"]]
        if d < MIN_LOG_M:
            msg, actions = (f"Only {d:.0f} m so far: a workout needs at least {MIN_LOG_M} m.",
                            [ui.button("Discard", lambda e: (app.close_dialog(), reset()), kind="text"),
                             ui.button("Keep going", lambda e: (app.close_dialog(), resume()))])
        else:
            def log(e):
                app.close_dialog()
                train.log_workout(app, {"exercise": state["activity"], "distance_m": round(d, 1),
                                        "duration_seconds": max(1, int(secs))}, lambda ok: ok and reset())
            msg, actions = (f"{name}: {d / 1000:.2f} km in {clock(secs)}, pace {pace(d, secs)}.",
                            [ui.button("Discard", lambda e: (app.close_dialog(), reset()), kind="text"),
                             ui.button("Keep going", lambda e: (app.close_dialog(), resume()), kind="ghost"),
                             ui.button("Log it", log)])
        app.page.show_dialog(ft.AlertDialog(modal=True, title=ft.Text("Finish this run?"), content=ft.Text(msg),
                                            actions=actions, actions_overflow_button_spacing=8))

    def leave():  # screen closed: end tracking so the GPS isn't left running
        state.update(mode="idle", left=True)
        drop_services()
    app.cleanups.append(leave)

    def pick(k):
        state["activity"] = k
    activity = ui.chips(ACTIVITIES, "walking", pick)
    render()
    return ui.screen(
        "Run / Walk",
        ui.card(ft.Column([
            ui.label("Activity"), activity,
            ft.Column([ui.label("Distance"), distance_text], spacing=0, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            ft.Row([ft.Column([ui.label("Time"), time_text], spacing=0, expand=True,
                              horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                    ft.Column([ui.label("Pace"), pace_text], spacing=0, expand=True,
                              horizontal_alignment=ft.CrossAxisAlignment.CENTER)]),
            signal_text, hint, buttons,
        ], spacing=14, horizontal_alignment=ft.CrossAxisAlignment.CENTER)),
        subtitle="Track distance with GPS. Only the total distance and time are saved, never your route.",
    )
