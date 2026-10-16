"""Signing up needs age 18+ and accepted Terms; an account asked to accept updated Terms can accept or sign out."""
import json

import flet as ft
import httpx

from fakes import FakeApp, button, fields, walk
from views import auth, legal

NOTICES = {"terms_of_use": {"version": "2026-10-16.v1", "title": "Terms of Use", "body": "t"},
           "privacy_notice": {"version": "2026-10-16.v1", "title": "Privacy Policy", "body": "p"},
           "cookie_policy": {"version": "2026-10-16.v1", "title": "Cookie Policy", "body": "c"}}


def signing_up(age: str):
    sent = []

    def handler(req):
        path = req.url.path
        if path == "/auth/v1/signup":
            return httpx.Response(200, json={"access_token": "a", "refresh_token": "r", "user": {"id": "u1"}})
        if path.endswith("/privacy"):
            return httpx.Response(200, json={"success": True, "notices": NOTICES})
        if path.endswith("/register"):
            sent.append(json.loads(req.content))
            return httpx.Response(200, json={"success": True})
        return httpx.Response(200, json={"profile": {"username": "ash"}})

    app = FakeApp(handler)
    screen = auth.signup(app)
    f = fields(screen)
    f["Email"].value, f["Username"].value, f[f"Age ({legal.MIN_AGE}+)"].value = "ash@example.com", "ash", age
    f["Password (8+ characters)"].value = f["Confirm password"].value = "pw123456"
    next(c for c in walk(screen) if isinstance(c, ft.Checkbox)).value = True
    button(screen, "Create account").on_click(None)
    shown = [c.value for c in walk(screen) if isinstance(c, ft.Text) and c.visible and c.value]
    return app, sent, shown


def test_signing_up_sends_age_and_the_accepted_versions():
    app, sent, _ = signing_up("18")
    assert app.screens == ["main"]
    assert sent[0]["age"] == 18 and sent[0]["terms_version"] == sent[0]["privacy_notice_version"] == "2026-10-16.v1"


def test_under_18_is_refused_before_any_account_is_made():
    app, sent, shown = signing_up("17")
    assert sent == [] and app.screens == [] and app.api.session is None
    assert f"Sorry, AWXCEND is for people {legal.MIN_AGE} and over." in shown


def test_which_documents_need_accepting():
    current = {"is_current": True}
    assert legal.outdated({"notices": NOTICES, "latest": {"terms_of_use": current, "privacy_notice": current}}) == []
    assert legal.outdated({"notices": NOTICES, "latest": {"privacy_notice": {"is_current": False}}}) == \
        ["terms_of_use", "privacy_notice"]  # never accepted the Terms, and an old privacy version
    assert legal.outdated({"notices": {}, "latest": {}}) == []  # migration not deployed yet: don't lock anyone out


def updated_terms():
    acks = []

    def handler(req):
        if req.method == "POST":
            acks.append(json.loads(req.content))
            return httpx.Response(200, json={"success": True})
        return httpx.Response(200, json={"success": True, "notices": NOTICES,
                                         "latest": {"privacy_notice": {"is_current": True}}})

    app = FakeApp(handler, profile={"username": "ash"})
    app.api.set_session({"access_token": "a", "refresh_token": "r", "user": {"id": "u1"}})
    legal.check_current(app)
    return app, acks, app.dialogs[-1]


def test_accepting_updated_terms_records_them():
    app, acks, dialog = updated_terms()
    button(dialog, "Accept").on_click(None)  # box not ticked
    assert acks == [] and app.dialogs == [dialog]
    next(c for c in walk(dialog) if isinstance(c, ft.Checkbox)).value = True
    button(dialog, "Accept").on_click(None)
    assert acks == [{"action": "acknowledge", "consent_type": "terms_of_use", "notice_version": "2026-10-16.v1"}]
    assert app.dialogs == []


def test_declining_updated_terms_signs_out():
    app, acks, dialog = updated_terms()
    button(dialog, "Sign out").on_click(None)
    assert acks == [] and app.screens == ["login"] and app.api.session is None
