"""Terms of Use, Privacy Policy and Cookie Policy. The texts are versioned on the server (privacy_notices),
so a change is published there and every app picks it up; accepting is recorded in user_consents."""
import flet as ft

import ui
from api import ApiError

MIN_AGE = 18  # Terms section 1; the server refuses younger sign-ups (MIN_AGE in _shared/validation.ts)
DOCS = [("terms_of_use", "Terms of Use"), ("privacy_notice", "Privacy Policy"),
        ("cookie_policy", "Cookie Policy")]
MUST_ACCEPT = ("terms_of_use", "privacy_notice")


def show(app, notices: dict, key: str) -> None:
    doc = notices.get(key)
    if not doc:
        app.toast("Couldn't load this document. Check your connection.", error=True)
        return
    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text(doc["title"]), scrollable=True,
        content=ft.Container(ft.Markdown(doc["body"], selectable=True,
                                         extension_set=ft.MarkdownExtensionSet.GITHUB_WEB), width=560),
        actions=[ui.button("Close", lambda e: app.close_dialog(), kind="text")]))


def agreement(text: str) -> tuple[ft.Checkbox, ft.Control]:
    """A checkbox with a long label that wraps on phones (a Checkbox's own label doesn't)."""
    box = ft.Checkbox(value=False)
    return box, ft.Row([box, ft.Text(text, size=13, color=ui.C.text, expand=True)],
                       vertical_alignment=ft.CrossAxisAlignment.START)


def links(app, notices: dict) -> ft.Control:
    """'Terms of Use · Privacy Policy · Cookie Policy' buttons for a form."""
    return ft.Row([ui.button(title, lambda e, k=key: show(app, notices, k), kind="text") for key, title in DOCS],
                  wrap=True, spacing=0)


def outdated(status: dict) -> list[str]:
    """The documents this account still has to accept (never accepted, or a newer version since)."""
    latest = status.get("latest") or {}
    return [k for k in MUST_ACCEPT if k in (status.get("notices") or {}) and not (latest.get(k) or {}).get("is_current")]


def check_current(app) -> None:
    """After sign-in: if the Terms or Privacy Policy changed since this account accepted them, ask again.
    Declining signs out (the account stays, and can be deleted from the next sign-in)."""
    try:
        status = app.api.call("privacy")
    except ApiError:
        return  # offline or a server hiccup: ask next time rather than lock the player out
    todo = outdated(status)
    if not todo:
        return
    notices = status["notices"]
    agree, agree_row = agreement(f"I am {MIN_AGE} or older and I agree to the updated documents.")

    def accept(e):
        if not agree.value:
            app.toast("Tick the box to continue, or sign out.", error=True)
            return
        try:
            for key in todo:
                app.api.call("privacy", "POST", {"action": "acknowledge", "consent_type": key,
                                                 "notice_version": notices[key]["version"]})
        except ApiError as ex:
            app.toast(str(ex), error=True)
            return
        app.close_dialog()

    def decline(e):
        app.close_dialog()
        app.sign_out()

    names = " and ".join(t for k, t in DOCS if k in todo)
    app.page.show_dialog(ft.AlertDialog(
        modal=True, title=ft.Text("We've updated our terms"),
        content=ft.Column([ft.Text(f"Please read and accept the {names} to keep using AWXCEND."),
                           links(app, notices), agree_row], tight=True, spacing=10, width=440),
        actions=[ui.button("Sign out", decline, kind="text"), ui.button("Accept", accept)]))


def view(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)

    def load():
        try:
            data = app.api.call("privacy")
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        notices, latest = data.get("notices") or {}, data.get("latest") or {}

        def row(key, title):
            doc, mine = notices.get(key) or {}, latest.get(key) or {}
            note = f"Version {doc.get('version', '-')}"
            if mine.get("acknowledged_at"):
                note += f" · you accepted {ui.when(mine['acknowledged_at'])}"
            return ui.card(ft.Row([ft.Icon(ft.Icons.GAVEL if key == "terms_of_use" else ft.Icons.SHIELD_OUTLINED
                                           if key == "privacy_notice" else ft.Icons.COOKIE_OUTLINED, color=ui.C.accent),
                                   ft.Column([ft.Text(title, color=ui.C.text, font_family="LatoBold"),
                                              ui.body(note, size=12)], spacing=2, expand=True),
                                   ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim)]),
                           padding=14, on_click=lambda e: show(app, notices, key))
        box.controls = [row(k, t) for k, t in DOCS]
        app.page.update()

    app.run(load)
    return ui.screen("Legal", box, subtitle=f"AWXCEND is a free, non-commercial student project for people "
                                            f"{MIN_AGE} and over. Your rights under the Data Privacy Act of 2012 "
                                            "are in the Privacy Policy.")
