"""AWXCEND entry point: session restore, auth gate, and the app shell (nav + screens)."""
import json

import flet as ft

import config
import ui
from api import Api, ApiError
from views import auth, food, home, profile, social, train

TABS = [
    ("home", "Home", ft.Icons.HOME_OUTLINED, ft.Icons.HOME),
    ("train", "Train", ft.Icons.FITNESS_CENTER_OUTLINED, ft.Icons.FITNESS_CENTER),
    ("food", "Food", ft.Icons.RESTAURANT_OUTLINED, ft.Icons.RESTAURANT),
    ("social", "Social", ft.Icons.GROUPS_OUTLINED, ft.Icons.GROUPS),
    ("profile", "Profile", ft.Icons.PERSON_OUTLINE, ft.Icons.PERSON),
]
SCREENS = {"home": home.view, "train": train.view, "food": food.view, "social": social.view, "profile": profile.view}
WIDE = 720  # px: side rail instead of the bottom bar


class App:
    def __init__(self, page: ft.Page, prefs: ft.SharedPreferences):
        self.page = page
        self.prefs = prefs
        self.api = Api(config.SUPABASE_URL, config.SUPABASE_KEY, on_session=self._on_session)
        self.me: dict | None = None      # the /profile payload
        self.tab = "home"
        self.stack: list[ft.Control] = []  # sub-screens opened over the current tab
        self.in_main = False
        self.cleanups: list = []  # run when leaving a screen (e.g. release the camera)
        self.body = ft.Container(expand=True)
        self.bar = ft.NavigationBar(
            destinations=[ft.NavigationBarDestination(icon=i, selected_icon=s, label=t) for _, t, i, s in TABS],
            on_change=lambda e: self.go(TABS[e.control.selected_index][0]),
            bgcolor=ui.fade(ui.C.panel, 0xf0), indicator_color=ui.fade(ui.C.primary, 0x40),
            indicator_shape=ui.CHAMFER, shadow_color=ui.C.primary, elevation=8,
            border=ft.Border(top=ft.BorderSide(1, ui.fade(ui.C.primary_bright, 0x55))),
        )
        self.rail = ft.NavigationRail(
            destinations=[ft.NavigationRailDestination(icon=i, selected_icon=s, label=t) for _, t, i, s in TABS],
            on_change=lambda e: self.go(TABS[e.control.selected_index][0]),
            label_type=ft.NavigationRailLabelType.ALL, bgcolor=ui.fade(ui.C.panel, 0xe0), min_width=84,
            leading=ft.Container(ft.Image(src="brand/awxcend-symbol.webp", width=40, height=40), padding=ft.Padding.only(top=12, bottom=12)),
            indicator_color=ui.fade(ui.C.primary, 0x40), indicator_shape=ui.CHAMFER,
        )

    # ---- platform --------------------------------------------------------------
    @property
    def is_desktop(self) -> bool:
        return self.page.platform in (ft.PagePlatform.WINDOWS, ft.PagePlatform.MACOS, ft.PagePlatform.LINUX)

    @property
    def is_staff(self) -> bool:
        return bool(self.me) and self.me["profile"].get("role") in ("admin", "moderator")

    def run(self, fn, *args) -> None:
        """Run blocking work (API calls) off the UI thread."""
        self.page.run_thread(fn, *args)

    def toast(self, message: str, error: bool = False) -> None:
        self.page.show_dialog(ft.SnackBar(ft.Text(message, color=ui.C.text),
                                          bgcolor=ui.fade(ui.C.danger, 0xdd) if error else ui.C.panel_alt))

    # ---- session ---------------------------------------------------------------
    def _on_session(self, session: dict | None) -> None:
        self.page.run_task(self.prefs.set, "session", json.dumps(session) if session else "")
        if session is None and self.me is not None:  # expired or signed out
            self.me = None
            self.show_auth()

    def load_me(self) -> dict:
        self.me = self.api.call("profile")
        return self.me

    def sign_out(self) -> None:
        self.me = None
        self.api.sign_out()
        self.show_auth()

    # ---- layout ----------------------------------------------------------------
    def leave(self) -> None:
        while self.cleanups:
            self.cleanups.pop()()

    def show_auth(self, screen: str = "login") -> None:
        self.leave()
        self.in_main = False
        self.stack.clear()
        self.page.controls[:] = [ui.backdrop(ft.SafeArea(auth.SCREENS[screen](self), expand=True))]
        self.page.update()

    def show_main(self) -> None:
        self.in_main = True
        self.stack.clear()
        self.layout()
        self.go(self.tab)

    def layout(self) -> None:
        wide = (self.page.width or 0) >= WIDE
        idx = [k for k, *_ in TABS].index(self.tab)
        self.bar.selected_index = self.rail.selected_index = idx
        if wide:
            edge = ft.Container(width=1, gradient=ft.LinearGradient(
                begin=ft.Alignment.TOP_CENTER, end=ft.Alignment.BOTTOM_CENTER,
                colors=[ui.fade(ui.C.primary_bright, 0x88), ui.fade(ui.C.accent, 0x55), ui.fade(ui.C.accent, 0)]))
            main = ft.Row([self.rail, edge, self.body], expand=True, spacing=0)
        else:
            main = ft.Column([self.body, self.bar], expand=True, spacing=0)
        self.page.controls[:] = [ui.backdrop(ft.SafeArea(main, expand=True))]

    def on_resize(self, e=None) -> None:
        if self.in_main:
            self.layout()
            self.page.update()

    def go(self, tab: str) -> None:
        self.leave()
        self.tab = tab
        self.stack.clear()
        self.bar.selected_index = self.rail.selected_index = [k for k, *_ in TABS].index(tab)
        self.body.content = SCREENS[tab](self)
        self.page.update()

    def open(self, build, *args) -> None:
        """Push a sub-screen (with a back arrow) over the current tab."""
        self.stack.append(self.body.content)
        back = ft.IconButton(ft.Icons.ARROW_BACK, on_click=lambda e: self.back(), tooltip="Back")
        self.body.content = ft.Column([ft.Container(back, padding=ft.Padding.only(left=8, top=8)), build(self, *args)],
                                      expand=True, spacing=0)
        self.page.update()

    def back(self) -> None:
        if self.stack:
            self.leave()
            self.body.content = self.stack.pop()
            self.page.update()


async def main(page: ft.Page):
    page.title = "AWXCEND"
    page.theme_mode = ft.ThemeMode.DARK
    page.theme = page.dark_theme = ui.theme()
    page.fonts = ui.FONTS
    page.bgcolor = ui.C.void
    page.padding = 0
    try:
        page.window.min_width, page.window.min_height = 380, 640
        page.window.width, page.window.height = 1100, 780
    except AttributeError:
        pass  # mobile: no window

    prefs = ft.SharedPreferences()
    app = App(page, prefs)
    app.picker = ft.FilePicker()
    page.services.append(app.picker)
    page.on_resize = app.on_resize

    if not config.SUPABASE_KEY:
        page.add(ui.screen("Setup needed", ui.error_box("config.py has no SUPABASE_KEY yet.")))
        return

    saved = await prefs.get("session")
    if not saved:
        app.show_auth()
        return
    app.api.session = json.loads(saved)
    page.add(ui.loading("Signing you in..."))

    def restore():
        try:
            app.load_me()
        except ApiError:
            app.api.session = None
            app.show_auth()
        else:
            app.show_main()

    app.run(restore)


def selfcheck(out_path: str) -> None:
    """`AWXCEND.exe --selfcheck result.txt`: prove a packaged build can run camera tracking (MediaPipe
    engine + pose model + OpenCV) without opening a window. Writes 'ok ...' or the error to out_path."""
    try:
        import numpy as np

        from pose.camera import MODEL, BaseOptions, mp, vision
        opts = vision.PoseLandmarkerOptions(base_options=BaseOptions(model_asset_path=MODEL),
                                            running_mode=vision.RunningMode.VIDEO)
        with vision.PoseLandmarker.create_from_options(opts) as landmarker:
            frame = np.zeros((480, 640, 3), np.uint8)
            landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=frame), 0)
        result = f"ok model={MODEL}"
    except Exception as e:  # report anything: this is a diagnostic
        result = f"FAILED {type(e).__name__}: {e}"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(result + "\n")


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 2 and sys.argv[1] == "--selfcheck":
        selfcheck(sys.argv[2])
    else:
        ft.run(main, assets_dir="assets")
