"""Login and forgot-password screens against a fake Supabase: what they send, and when, through the real views."""
import json

import flet as ft
import httpx

import ui
from fakes import FakeApp, walk
from views.auth import forgot, login

LINK = "https://example.supabase.co/auth/v1/verify?token={}&type=recovery&redirect_to=http://localhost:3000"
SESSION = {"access_token": "tok", "refresh_token": "ref", "user": {"id": "u1"}}


def screen(handler):
    app = FakeApp(handler)
    root = forgot(app)
    field = {c.label: c for c in walk(root) if isinstance(c, ft.TextField)}
    button = next(c for c in walk(root) if isinstance(c, ft.FilledButton))
    error = next(c for c in walk(root) if isinstance(c, ft.Text) and c.color == ui.C.danger)

    def submit(link=None, pw="newpass123", confirm=None):
        if link is not None:
            field["Reset link from the email"].value = link
        field["New password (8+ chars)"].value = pw
        field["Confirm new password"].value = pw if confirm is None else confirm
        button.on_click(None)

    field["Email"].value = "a@example.com"
    button.on_click(None)  # step 1: send the email
    return app, submit, error


def supabase(refuse_first_password: bool):
    calls = []

    def handler(req):
        calls.append(f"{req.method} {req.url.path}")
        if req.url.path == "/auth/v1/verify":
            return httpx.Response(200, json={**SESSION, "access_token": json.loads(req.content)["token_hash"]})
        if req.method == "PUT" and refuse_first_password and calls.count("PUT /auth/v1/user") == 1:
            return httpx.Response(422, json={"code": 422, "error_code": "same_password",
                                             "msg": "New password should be different from the old password."})
        if req.url.path == "/functions/v1/profile":
            return httpx.Response(200, json={"profile": {"id": "u1"}})
        return httpx.Response(200, json={})
    return calls, handler


def test_a_retry_after_a_refused_password_reuses_the_link_and_a_new_link_signs_in_again():
    calls, handler = supabase(refuse_first_password=True)
    app, submit, error = screen(handler)
    submit(LINK.format("aa"), confirm="typo-pass1")
    assert error.value == "The new passwords don't match." and calls == ["POST /auth/v1/recover"]

    submit()
    assert "different from the old password" in error.value
    submit()  # same link again: it can't sign in twice, so only the password is retried
    assert calls.count("POST /auth/v1/verify") == 1 and calls.count("PUT /auth/v1/user") == 2
    assert app.screens == ["main"] and app.toasts == ["Password updated."]


def test_a_new_link_is_verified_and_leaving_early_drops_its_sign_in():
    calls, handler = supabase(refuse_first_password=True)
    app, submit, _ = screen(handler)
    submit(LINK.format("aa"))  # signs in, password refused
    submit(LINK.format("bb"))  # a fresh link from a new email signs in again
    assert calls.count("POST /auth/v1/verify") == 2 and app.api.session["access_token"] == "bb"

    _, handler = supabase(refuse_first_password=True)
    app, submit, _ = screen(handler)
    submit(LINK.format("aa"))  # signed in by the link, password refused...
    app.show_auth("login")      # ...then "Back to log in"
    assert app.api.session is None and app.saved[-1] is None  # not signed in on the next launch


def log_in(handler):
    app = FakeApp(handler)
    root = login(app)
    field = {c.label: c for c in walk(root) if isinstance(c, ft.TextField)}
    field["Email"].value, field["Password"].value = "a@example.com", "pw123456"
    next(c for c in walk(root) if isinstance(c, ft.FilledButton)).on_click(None)
    return app


def test_a_failed_login_keeps_the_saved_session_but_a_half_login_is_not_saved():
    def offline(req):
        raise httpx.ConnectError("offline")

    assert log_in(offline).saved == []  # nothing overwritten: the saved login still works next launch

    def no_profile(req):
        if req.url.path == "/auth/v1/token":
            return httpx.Response(200, json=SESSION)
        return httpx.Response(400, json={"success": False, "error": "Profile not found"})

    app = log_in(no_profile)
    assert app.saved[-1] is None and app.screens == []  # signed in, profile failed: not kept
