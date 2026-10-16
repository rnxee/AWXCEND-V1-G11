"""A stand-in for main.App that drives real views without a Flet page: work runs inline, dialogs
are kept in a list, and Supabase is an httpx.MockTransport."""
import flet as ft
import httpx

from api import Api


class FakeApp:
    def __init__(self, handler, profile: dict | None = None):
        self.saved = []
        self.api = Api("https://example.supabase.co", "pub", transport=httpx.MockTransport(handler),
                       on_session=self.saved.append)
        self.dialogs: list = []
        app = self

        class Page:
            def update(self, *controls):
                pass

            def show_dialog(self, dlg):
                app.dialogs.append(dlg)

        self.page = Page()
        self.me = {"profile": profile} if profile else None
        self.cleanups, self.toasts, self.screens = [], [], []

    def run(self, fn, *args):
        fn(*args)

    def toast(self, message, error=False):
        self.toasts.append(message)

    def close_dialog(self):
        if self.dialogs:
            self.dialogs.pop()

    def load_me(self):
        self.me = self.api.call("profile")

    def show_main(self):
        self.screens.append("main")

    def show_auth(self, screen="login"):
        while self.cleanups:  # like App.leave()
            self.cleanups.pop()()
        self.screens.append(screen)


def walk(c):
    yield c
    for child in [getattr(c, "content", None), *(getattr(c, "controls", None) or []), *(getattr(c, "actions", None) or [])]:
        if isinstance(child, ft.Control):
            yield from walk(child)


def fields(root) -> dict:
    return {c.label: c for c in walk(root) if isinstance(c, ft.TextField)}


def button(root, text: str):
    return next(c for c in walk(root) if isinstance(c, (ft.FilledButton, ft.TextButton, ft.OutlinedButton))
                and c.content == text)


def sign_out(app):
    app.api.set_session(None)
    app.show_auth()


FakeApp.sign_out = sign_out
