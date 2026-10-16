"""Account & privacy: report a problem, download my data, the relative strength board,
hiding the account (deactivate) and deleting it. Every action is checked by the server."""
import asyncio
import json
import os
from datetime import date

import flet as ft

import ui
from api import ApiError
from views import legal

BUG_CATEGORIES = [("bug", "Something's broken"), ("feature_request", "Idea"), ("other", "Other")]
FULL = float("inf")  # a card as wide as the screen, whatever its text


def set_active(app, active: bool, after) -> None:
    """Hide (deactivate) or show the account, reload the profile, then `after()` to redraw."""
    def work():
        try:
            app.api.call("set-account-active", "POST", {"active": active})
            app.load_me()
        except ApiError as ex:
            app.toast(str(ex), error=True)
            return
        app.toast("Your account is visible again." if active else "Your account is hidden.")
        after()
    app.run(work)


def report_problem(app) -> None:
    """A problem with the app itself (not a player: that's Report on their profile)."""
    kind = {"v": "bug"}
    text = ui.field("What happened? Steps to repeat it help", multiline=True, min_lines=3, max_lines=6,
                    max_length=1000)

    def send(e):
        if not text.value.strip():
            app.toast("Describe the problem first.", error=True)
            return
        body = {"category": kind["v"], "description": text.value.strip()}
        app.close_dialog()

        def work():
            try:
                app.api.call("report-bug", "POST", body)
                app.toast("Thanks - the team will look at it.")
            except ApiError as ex:
                app.toast(str(ex), error=True)
        app.run(work)

    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text("Report a problem"),
        content=ft.Column([ui.chips(BUG_CATEGORIES, "bug", lambda k: kind.update(v=k)), text],
                          tight=True, spacing=12, width=440),
        actions=[ui.button("Cancel", lambda e: app.close_dialog(), kind="text"), ui.button("Send", send)]))


def view(app) -> ft.Control:
    p = app.me["profile"]
    hidden = bool(p.get("deactivated_at"))
    board = ft.Column([ui.loading()], spacing=10)

    # ---- download my data -------------------------------------------------------------
    async def download(e):
        try:
            data = await asyncio.to_thread(app.api.call, "export-my-data")
        except ApiError as ex:
            app.toast(str(ex), error=True)
            return
        raw = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
        path = await app.picker.save_file(dialog_title="Save your AWXCEND data",
                                          file_name=f"awxcend-my-data-{date.today()}.json", src_bytes=raw)
        if not path:
            return  # cancelled
        try:
            if app.is_desktop:  # on desktop the dialog only picks the place (also when overwriting)
                with open(path, "wb") as f:
                    f.write(raw)
        except OSError as ex:
            app.toast(f"Couldn't save the file: {ex}", error=True)
            return
        app.toast(f"Saved {os.path.basename(path)}")

    # ---- relative strength board (needs its own notice) ---------------------------------
    def load_board():
        try:
            res = app.api.call("privacy")
        except ApiError as ex:
            board.controls = [ui.error_box(str(ex), lambda: app.run(load_board))]
            app.page.update()
            return
        notice = (res.get("notices") or {}).get("relative_leaderboard") or {}
        switch = ft.Switch(value=bool(res.get("relative_leaderboard_opt_in")), active_color=ui.C.accent)

        def save(opt_in: bool):
            def work():
                try:
                    app.api.call("privacy", "POST", {"action": "set_relative_leaderboard", "opt_in": opt_in,
                                                     "notice_version": notice.get("version")})
                    app.toast("You're on the relative board." if opt_in else "You left the relative board.")
                except ApiError as ex:
                    app.toast(str(ex), error=True)
                load_board()
            app.run(work)

        def changed(e):
            if not switch.value:
                save(False)
                return
            switch.value = False  # only on once the notice is accepted
            switch.update()

            def join(e):
                app.close_dialog()
                save(True)
            app.page.show_dialog(ft.AlertDialog(
                title=ft.Text(notice.get("title", "Relative strength board")), scrollable=True,
                content=ft.Container(ft.Markdown(notice.get("body", "")), width=520),
                actions=[ui.button("Not now", lambda e: app.close_dialog(), kind="text"),
                         ui.button("Join", join, kind="accent")]))

        switch.on_change = changed
        board.controls = [ui.card(ft.Row([
            ft.Column([
                ft.Text("Show my lifts as a multiple of my bodyweight", color=ui.C.text),
                ui.body("Others then see your multiple and strength tier on the strength leaderboard, which can "
                        "hint at your bodyweight. Your bodyweight itself is never shown.", size=12),
            ], spacing=6, expand=True),
            switch,
        ], vertical_alignment=ft.CrossAxisAlignment.START), padding=14)]
        app.page.update()

    # ---- hide / show the account ------------------------------------------------------
    def reopen():
        app.back()
        app.open(view)

    def confirm_hide(e):
        def go(e):
            app.close_dialog()
            set_active(app, False, reopen)
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text("Hide your account?"),
            content=ft.Text("You'll disappear from leaderboards, search, friends' lists and the feed. Nothing is "
                            "deleted, and you can show your account again here at any time."),
            actions=[ui.button("Cancel", lambda e: app.close_dialog(), kind="text"),
                     ui.button("Hide account", go, kind="danger")]))

    # ---- delete ------------------------------------------------------------------------
    def confirm_delete(e):
        name = ui.field(f"Type your username ({p.get('username')})")
        password = ui.field("Password", password=True, can_reveal_password=True)
        error = ft.Text("", color=ui.C.danger, visible=False)
        go_btn = ui.button("Delete forever", None, kind="danger")

        def go(e):
            if not name.value.strip() or not password.value:
                error.value, error.visible = "Enter your username and password.", True
                app.page.update()
                return
            go_btn.disabled, error.visible = True, False
            app.page.update()

            def work():
                try:
                    app.api.call("delete-account", "POST", {"confirm_username": name.value.strip(),
                                                            "password": password.value})
                except ApiError as ex:
                    error.value, error.visible, go_btn.disabled = str(ex), True, False
                    app.page.update()
                    return
                app.close_dialog()
                app.me = None
                app.api.set_session(None)  # the login no longer exists
                app.show_auth()
                app.toast("Your account and its data were deleted.")
            app.run(work)

        go_btn.on_click = go
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text("Delete your account?"),
            content=ft.Column([
                ui.body("This removes your profile, workouts, meals, posts, messages and friends for good. "
                        "It can't be undone. Download your data first if you want a copy.", color=ui.C.text),
                name, password, error], tight=True, spacing=12, width=440),
            actions=[ui.button("Cancel", lambda e: app.close_dialog(), kind="text"), go_btn]))

    app.run(load_board)
    visibility = (ui.body("Your account is hidden from other players.", color=ui.C.gold) if hidden
                  else ui.body("Other players can find you in search, leaderboards and the feed."))
    return ui.screen(
        "Account",
        ui.section("Your data"),
        ui.card(ft.Column([
            ui.body("Download everything AWXCEND stores about you, as a JSON file.", color=ui.C.text),
            ui.button("Download my data", download, icon=ft.Icons.DOWNLOAD, kind="ghost"),
        ], spacing=10), padding=14, width=FULL),
        ui.section("Strength leaderboard"), board,
        ui.section("Legal"),
        ui.card(ft.Column([
            ui.body("Terms of Use, Privacy Policy and Cookie Policy, with the versions you accepted.", color=ui.C.text),
            ui.button("Read the legal documents", lambda e: app.open(legal.view), icon=ft.Icons.GAVEL, kind="ghost"),
        ], spacing=10), padding=14, width=FULL),
        ui.section("Account"),
        ui.card(ft.Column([
            visibility,
            ui.button("Show my account", lambda e: set_active(app, True, reopen), icon=ft.Icons.VISIBILITY,
                      kind="ghost") if hidden
            else ui.button("Hide my account", confirm_hide, icon=ft.Icons.VISIBILITY_OFF, kind="ghost"),
        ], spacing=10), padding=14, width=FULL),
        ui.card(ft.Column([
            ui.heading("Delete account", 15, ui.C.danger),
            ui.body("Permanently removes your account and everything in it.", size=13),
            ui.button("Delete my account", confirm_delete, icon=ft.Icons.DELETE_FOREVER, kind="danger"),
        ], spacing=10), padding=14, accent=ui.fade(ui.C.danger, 0x88), width=FULL),
        subtitle="Your data, your visibility, and leaving AWXCEND.",
    )
