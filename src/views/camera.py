"""Camera workout (desktop): pick an exercise, count reps live, then confirm and save.

The counted reps pre-fill a normal manual log that the user confirms: these counters are
not server-validated, so the save never claims camera-verified credit.
"""
import flet as ft

import ui
from pose.camera import CameraSession
from pose.counters import EXERCISES
from pose.source import parse_source
from views.train import log_workout


CAMERAS = [("0", "Webcam 1"), ("1", "Webcam 2"), ("2", "Webcam 3"), ("phone", "Phone over Wi-Fi")]
PHONE_HELP = ("Phone over Wi-Fi: install IP Webcam (Android, free). In Video preferences set Video resolution to "
              "640x480 (bigger frames can't cross Wi-Fi fast enough and reps get lost), then tap Start server and "
              "type the address it shows. Keep the phone and this computer on the same Wi-Fi. Stand the phone "
              "sideways (landscape): if the video here looks tipped over, push-ups can't be counted. Using Phone "
              "Link, DroidCam or Iriun instead? Your phone appears as Webcam 2 or 3.")
MIN_GOOD_FPS = 18  # below this, fast reps can fall between frames


def view(app) -> ft.Control:
    state = {"key": "pushup", "session": None}
    img = ft.Image(src="brand/awxcend-symbol.webp", fit=ft.BoxFit.CONTAIN, gapless_playback=True,
                   border_radius=12, expand=True)
    reps = ui.num(0, 56, ui.C.camera)
    feedback = ft.Text("", size=16, color=ui.C.text, text_align=ft.TextAlign.CENTER)
    angle = ui.body("", size=12)
    stream = ft.Text("", size=12, color=ui.C.dim, text_align=ft.TextAlign.CENTER)
    tip = ui.body(EXERCISES["pushup"].tip, color=ui.C.text, expand=True)
    start = ui.button("Start", None, icon=ft.Icons.PLAY_ARROW, kind="camera", height=48)
    stop = ui.button("Finish", None, icon=ft.Icons.STOP, kind="danger", height=48, visible=False)

    def pick(key):
        state["key"] = key
        tip.value = EXERCISES[key].tip
        tip.update()

    picker = ui.chips([(k, ex.label) for k, ex in EXERCISES.items()], "pushup", pick)

    # Camera source: a webcam (a phone via Phone Link / DroidCam / Iriun shows up as one) or a
    # phone streaming over Wi-Fi (IP Webcam app). The choice is remembered on this computer.
    cam = ui.dropdown("Camera", CAMERAS, "0", expand=True)
    phone_url = ui.field("Phone address (from the IP Webcam app)", hint_text="192.168.1.5:8080",
                         expand=True, visible=False)
    cam_help = ui.body(PHONE_HELP, size=12, visible=False)

    def on_cam(e=None):
        phone_url.visible = cam_help.visible = cam.value == "phone"
        app.page.update()

    cam.on_select = on_cam

    async def load_choice():
        choice, url = await app.prefs.get("camera.choice"), await app.prefs.get("camera.url")
        if choice in dict(CAMERAS):
            cam.value = choice
        phone_url.value = url or ""
        on_cam()

    app.page.run_task(load_choice)

    def on_frame(jpg: bytes, counter, countdown_left: float):
        img.src = jpg
        reps.value = str(counter.reps)
        feedback.value = "Get ready..." if countdown_left else counter.feedback
        angle.value = f"Joint angle {counter.signal:.0f}°" if counter.signal is not None else ""
        reader = state["session"].reader if state["session"] else None
        if reader and reader.fps:
            w, h = reader.size
            slow = reader.fps < MIN_GOOD_FPS
            stream.value = f"Camera {w}×{h} · {reader.fps:.0f} fps" + (
                " - too slow, reps may be missed. " + ("Set IP Webcam to 640x480." if cam.value == "phone"
                                                       else "Close other apps using the camera.") if slow else "")
            stream.color = ui.C.gold if slow else ui.C.dim
        app.page.update(img, reps, feedback, angle, stream)  # only what changed: this runs every frame

    def on_error(msg: str):
        app.toast(msg, error=True)
        halt()

    def halt():
        if state["session"]:
            state["session"].stop()
            state["session"] = None
        start.visible, stop.visible = True, False
        picker.disabled = cam.disabled = phone_url.disabled = False
        app.page.update()

    def begin(e):
        try:
            source = parse_source(phone_url.value) if cam.value == "phone" else int(cam.value)
        except ValueError as ex:
            app.toast(str(ex), error=True)
            return
        app.page.run_task(app.prefs.set, "camera.choice", cam.value)
        app.page.run_task(app.prefs.set, "camera.url", phone_url.value.strip())
        session = CameraSession(state["key"], on_frame, on_error, source=source)
        state["session"] = session
        app.cleanups.append(halt)
        start.visible, stop.visible = False, True
        picker.disabled = cam.disabled = phone_url.disabled = True
        reps.value, feedback.value = "0", "Connecting to your phone..." if cam.value == "phone" else "Starting camera..."
        app.page.update()
        session.start()

    def finish(e):
        session = state["session"]
        counted = session.counter.reps if session else 0
        halt()
        confirm(counted)

    def confirm(counted: int):
        ex = EXERCISES[state["key"]]
        rep_f = ui.number_field("Reps", counted, expand=True)
        weight_f = ui.number_field("Weight (kg, optional)", "", decimals=True, expand=True)

        def save(e):
            r = int(rep_f.value or 0)
            if not 1 <= r <= 300:
                app.toast("Reps must be 1-300.", error=True)
                return
            app.page.pop_dialog()
            w = float(weight_f.value) if weight_f.value else None
            log_workout(app, {"exercise": ex.log_as, "sets": 1, "reps": r, "weight_kg": w})

        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text(f"Save {ex.label} set?"),
            content=ft.Column([ui.body(f"The camera counted {counted} rep{'s' if counted != 1 else ''}. "
                                       "Fix the number if it missed any, then save."),
                               ft.Row([rep_f, weight_f], spacing=10)], tight=True, spacing=12, width=420),
            actions=[ui.button("Discard", lambda e: app.page.pop_dialog(), kind="text"),
                     ui.button("Save set", save, icon=ft.Icons.CHECK, kind="camera")]))

    start.on_click, stop.on_click = begin, finish

    stage = ft.Container(img, bgcolor=ui.C.panel, border_radius=12, border=ft.Border.all(1, ui.fade(ui.C.camera, 0x55)),
                         height=420, alignment=ft.Alignment.CENTER)
    hud = ui.card(ft.Column([ui.label("Reps", ui.C.camera), reps, feedback, angle, stream],
                            horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=6), padding=14)
    return ui.screen(
        "Camera workout", picker,
        ft.Row([cam, phone_url], spacing=10, wrap=False), cam_help,
        ui.card(ft.Row([ft.Icon(ft.Icons.LIGHTBULB_OUTLINE, color=ui.C.gold), tip], spacing=10), padding=12),
        stage, hud, ft.Row([start, stop], alignment=ft.MainAxisAlignment.CENTER),
        ui.body("Good light and your whole body in frame make counting reliable. "
                "Video stays between your camera and this computer.", size=12, text_align=ft.TextAlign.CENTER),
    )
