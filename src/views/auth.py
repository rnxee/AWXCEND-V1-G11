"""Login, signup (privacy notice + /register), and forgot password (paste the emailed reset link)."""
import re

import flet as ft

import ui
from api import ApiError

EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _frame(app, *controls) -> ft.Control:
    logo = ft.Image(src="brand/awxcend-wordmark.webp", width=240, fit=ft.BoxFit.CONTAIN)
    tagline = ft.Text("AWAKEN · EXPERIENCE · ASCEND", size=10, color=ui.C.dim, font_family="Michroma",
                      style=ft.TextStyle(letter_spacing=2))
    marker = ft.Row([ui.diamond(ui.C.primary_bright, 7), ui.label("System access", ui.C.primary_bright, 11)],
                    spacing=8, alignment=ft.MainAxisAlignment.CENTER)
    col = ft.Column([ft.Container(logo, alignment=ft.Alignment.CENTER, padding=ft.Padding.only(top=12, bottom=2)),
                     ft.Container(tagline, alignment=ft.Alignment.CENTER), ft.Container(height=6), marker,
                     *controls], spacing=14, scroll=ft.ScrollMode.AUTO, width=420)
    return ft.Container(col, alignment=ft.Alignment.CENTER, padding=24, expand=True)


def _busy(btn: ft.Control, on: bool, text: str) -> None:
    btn.disabled = on
    btn.content = "Please wait..." if on else text


def login(app) -> ft.Control:
    email = ui.field("Email", keyboard_type=ft.KeyboardType.EMAIL, autofocus=True)
    password = ui.field("Password", password=True, can_reveal_password=True)
    error = ft.Text("", color=ui.C.danger, visible=False)

    def submit(e=None):
        if not EMAIL.match(email.value.strip()) or not password.value:
            error.value, error.visible = "Enter your email and password.", True
            app.page.update()
            return
        _busy(go_btn, True, "Log in")
        error.visible = False
        app.page.update()
        app.run(work)

    def work():
        try:
            app.api.sign_in(email.value.strip(), password.value)
            app.load_me()
        except ApiError as ex:
            error.value, error.visible = str(ex), True
            _busy(go_btn, False, "Log in")
            app.page.update()
            return
        app.show_main()

    password.on_submit = submit
    go_btn = ui.button("Log in", submit, width=float("inf"))
    return _frame(app, ui.card(ft.Column([
        ui.heading("Welcome back", 20), email, password, error, go_btn,
        ft.Row([ui.button("Forgot password?", lambda e: app.show_auth("forgot"), kind="text"),
                ui.button("Create account", lambda e: app.show_auth("signup"), kind="text")],
               alignment=ft.MainAxisAlignment.SPACE_BETWEEN, wrap=True),
    ], spacing=12, horizontal_alignment=ft.CrossAxisAlignment.STRETCH), padding=20))


def signup(app) -> ft.Control:
    email = ui.field("Email", keyboard_type=ft.KeyboardType.EMAIL, autofocus=True)
    password = ui.field("Password (8+ characters)", password=True, can_reveal_password=True)
    confirm = ui.field("Confirm password", password=True, can_reveal_password=True)
    username = ui.field("Username", max_length=30)
    path = ui.dropdown("Training path", ui.FOCUS_TYPES, "hybrid", expand=True)
    weight = ui.number_field("Weight (kg)", decimals=True, expand=True)
    height = ui.number_field("Height (cm)", decimals=True, expand=True)
    age = ui.number_field("Age", expand=True)
    sex = ui.dropdown("Sex", [("male", "Male"), ("female", "Female")], expand=True)
    goal = ui.dropdown("Goal", [("bulk", "Bulk"), ("cut", "Cut"), ("maintain", "Maintain")], expand=True)
    agree = ft.Checkbox(label="I have read the privacy notice", value=False)
    error = ft.Text("", color=ui.C.danger, visible=False)
    notice: dict = {}

    def load_notice():
        try:
            data = app.api.call("privacy", anon=True)
            notice.update(data["notices"]["privacy_notice"])
        except (ApiError, KeyError, TypeError):
            pass  # checked again on submit

    def read_notice(e):
        if not notice:
            app.toast("Couldn't load the privacy notice. Check your connection.", error=True)
            return
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text(notice["title"]), scrollable=True,
            content=ft.Container(ft.Markdown(notice["body"]), width=520),
            actions=[ui.button("Close", lambda e: app.page.pop_dialog(), kind="text")]))

    def fail(msg: str):
        error.value, error.visible = msg, True
        _busy(go_btn, False, "Create account")
        app.page.update()

    def submit(e=None):
        u = username.value.strip()
        problems = []
        if not EMAIL.match(email.value.strip()):
            problems.append("a valid email")
        if len(password.value) < 8:
            problems.append("a password of 8+ characters")
        elif password.value != confirm.value:
            problems.append("matching passwords")
        if not u:
            problems.append("a username")
        if not agree.value:
            problems.append("to read and accept the privacy notice")
        if problems:
            fail("Please add " + ", ".join(problems) + ".")
            return
        _busy(go_btn, True, "Create account")
        error.visible = False
        app.page.update()
        app.run(work, u)

    def work(u: str):
        if not notice:
            load_notice()
        if not notice:
            fail("Couldn't load the privacy notice. Check your connection and try again.")
            return
        try:
            if app.api.sign_up(email.value.strip(), password.value) is None:
                fail("Check your email to confirm your account, then log in.")
                return
        except ApiError as ex:
            fail(str(ex))
            return
        body = {"username": u, "privacy_notice_version": notice["version"], "focus_type": path.value,
                "weight_kg": float(weight.value) if weight.value else None,
                "height_cm": float(height.value) if height.value else None,
                "age": int(age.value) if age.value else None, "sex": sex.value, "goal": goal.value}
        try:
            app.api.call("register", "POST", body)
            app.load_me()
        except ApiError as ex:
            # No profile row means an unusable login: remove it so the email can sign up again.
            try:
                app.api.call("abandon-signup", "POST")
            except ApiError:
                pass
            app.api.set_session(None)
            fail("That username is taken - pick another." if ex.code == "USERNAME_TAKEN" else str(ex))
            return
        app.show_main()

    go_btn = ui.button("Create account", submit, width=float("inf"))
    app.run(load_notice)
    return _frame(app, ui.card(ft.Column([
        ui.heading("Create your account", 20), email, password, confirm, username, path,
        ft.ExpansionTile(title=ft.Text("About you (optional)"), controls_padding=ft.Padding.only(top=8),
                         controls=[ft.Column([ft.Row([weight, height]), ft.Row([age, sex]), goal], spacing=10)]),
        ft.Row([agree, ui.button("Read notice", read_notice, kind="text")], wrap=True),
        error, go_btn,
        ui.button("I already have an account", lambda e: app.show_auth("login"), kind="text"),
    ], spacing=12, horizontal_alignment=ft.CrossAxisAlignment.STRETCH), padding=20))


def forgot(app) -> ft.Control:
    email = ui.field("Email", keyboard_type=ft.KeyboardType.EMAIL, autofocus=True)
    code = ui.field("Paste the reset link from the email", multiline=True, max_lines=3)
    new_pw = ui.field("New password (8+ characters)", password=True, can_reveal_password=True)
    step2 = ft.Column([code, new_pw], spacing=12, visible=False)
    info = ft.Text("", color=ui.C.dim)
    error = ft.Text("", color=ui.C.danger, visible=False)

    def fail(msg):
        error.value, error.visible = msg, True
        _busy(go_btn, False, "Reset password" if step2.visible else "Send reset email")
        app.page.update()

    def submit(e=None):
        error.visible = False
        if not EMAIL.match(email.value.strip()):
            fail("Enter the email you signed up with.")
            return
        if step2.visible and (not code.value.strip() or len(new_pw.value) < 8):
            fail("Paste the reset link and enter a new password of 8+ characters.")
            return
        _busy(go_btn, True, "")
        app.page.update()
        app.run(work)

    def work():
        try:
            if not step2.visible:
                app.api.send_recovery_code(email.value.strip())
                step2.visible = True
                info.value = ("We emailed you a reset link. Copy the link (right-click or long-press it, "
                              "then Copy link) and paste it below. If you already opened it, paste the "
                              "address of the page it opened instead.")
                _busy(go_btn, False, "Reset password")
                app.page.update()
                return
            app.api.recover(email.value.strip(), code.value)
            app.api.set_password(new_pw.value)
            app.load_me()
        except ApiError as ex:
            fail(str(ex))
            return
        app.toast("Password updated.")
        app.show_main()

    go_btn = ui.button("Send reset email", submit, width=float("inf"))
    return _frame(app, ui.card(ft.Column([
        ui.heading("Reset your password", 20), email, info, step2, error, go_btn,
        ui.button("Back to log in", lambda e: app.show_auth("login"), kind="text"),
    ], spacing=12, horizontal_alignment=ft.CrossAxisAlignment.STRETCH), padding=20))


SCREENS = {"login": login, "signup": signup, "forgot": forgot}
