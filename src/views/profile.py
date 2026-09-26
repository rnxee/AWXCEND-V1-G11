"""Profile tab (own profile + edit) and public profiles of other users."""
import flet as ft

import ui
from api import ApiError
from views.home import workout_line

SEX = [("male", "Male"), ("female", "Female")]
GOALS = [("bulk", "Bulk"), ("cut", "Cut"), ("maintain", "Maintain")]


def _header(p: dict, lvl: dict, color: str = ui.C.accent) -> ft.Control:
    need = lvl.get("xpForNextLevel") or 1
    return ui.card(ft.Column([
        ft.Row([ui.avatar(p.get("username", "?"), 64, color),
                ft.Column([ui.heading(p.get("username", ""), 20),
                           ft.Row([ui.tag(ui.rank_text(p), ui.C.gold),
                                   ui.tag(ui.FOCUS_LABEL.get(p.get("focus_type"), "Hybrid Athlete"), color)],
                                  spacing=6, wrap=True)], spacing=6, expand=True),
                ft.Column([ui.label("Level", ui.C.dim, 10), ui.num(lvl.get("level", 1), 34, color)],
                          horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=0)],
               vertical_alignment=ft.CrossAxisAlignment.CENTER),
        ui.body(p.get("bio") or "No bio yet.", color=ui.C.text if p.get("bio") else ui.C.faint),
        ui.xp_bar((lvl.get("xpIntoLevel") or 0) / need, height=10),
    ], spacing=12), padding=18, accent=color)


def _attributes(p: dict) -> ft.Control:
    return ft.Row([ui.stat("Strength", int(p.get("strength") or 0), ui.C.danger, ft.Icons.FITNESS_CENTER),
                   ui.stat("Agility", int(p.get("agility") or 0), ui.C.camera, ft.Icons.DIRECTIONS_RUN),
                   ui.stat("Vitality", int(p.get("vitality") or 0), ui.C.food, ft.Icons.FAVORITE_OUTLINE)], spacing=10)


def edit_dialog(app) -> None:
    p = app.me["profile"]
    username = ui.field("Username", value=p.get("username") or "", max_length=30)
    bio = ui.field("Bio", value=p.get("bio") or "", multiline=True, max_lines=4, max_length=300)
    path = ui.dropdown("Training path", ui.FOCUS_TYPES, p.get("focus_type") or "hybrid")
    weight = ui.number_field("Weight (kg)", p.get("weight_kg") or "", decimals=True, expand=True)
    height = ui.number_field("Height (cm)", p.get("height_cm") or "", decimals=True, expand=True)
    age = ui.number_field("Age", p.get("age") or "", expand=True)
    sex = ui.dropdown("Sex", SEX, p.get("sex"), expand=True)
    goal = ui.dropdown("Goal", GOALS, p.get("goal"))

    def save(e):
        if not username.value.strip():
            app.toast("Username can't be empty.", error=True)
            return
        # update-profile clears any optional field left out, so always send all of them.
        body = {"username": username.value.strip(), "bio": bio.value.strip() or None, "focus_type": path.value,
                "weight_kg": float(weight.value) if weight.value else None,
                "height_cm": float(height.value) if height.value else None,
                "age": int(age.value) if age.value else None, "sex": sex.value, "goal": goal.value}
        app.page.pop_dialog()

        def work():
            try:
                app.api.call("update-profile", "POST", body)
                app.load_me()
            except ApiError as ex:
                app.toast(str(ex), error=True)
                return
            app.toast("Profile saved.")
            app.go("profile")
        app.run(work)

    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text("Edit profile"), scrollable=True,
        content=ft.Column([username, bio, path, ui.body("You can change your path once every 30 days.", size=12),
                           ft.Row([weight, height]), ft.Row([age, sex]), goal], tight=True, spacing=12, width=460),
        actions=[ui.button("Cancel", lambda e: app.page.pop_dialog(), kind="text"), ui.button("Save", save)]))


def view(app) -> ft.Control:
    from views import admin, coach, social
    me, p = app.me, app.me["profile"]
    body_stats = [(k, v) for k, v in (("Weight", f"{p['weight_kg']:g} kg" if p.get("weight_kg") else None),
                                     ("Height", f"{p['height_cm']:g} cm" if p.get("height_cm") else None),
                                     ("Age", p.get("age")), ("Goal", (p.get("goal") or "").title() or None)) if v]

    def link(text, icon, on_click, color=ui.C.text):
        return ui.card(ft.Row([ft.Icon(icon, color=color), ft.Text(text, color=color, expand=True),
                               ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim)]), padding=14, on_click=on_click)

    links = [link("Leaderboard", ft.Icons.LEADERBOARD, lambda e: app.open(social.leaderboard)),
             link("AI coach", ft.Icons.AUTO_AWESOME, lambda e: app.open(coach.view))]
    if app.is_staff:
        links.append(link("Admin panel", ft.Icons.ADMIN_PANEL_SETTINGS, lambda e: app.open(admin.view), ui.C.gold))
    links.append(link("Sign out", ft.Icons.LOGOUT, lambda e: app.sign_out(), ui.C.danger))

    return ui.screen(
        "Profile", _header(p, me.get("levelInfo") or {}),
        ft.Row([ui.stat("XP", int(p.get("xp") or 0), ui.C.primary_bright, ft.Icons.BOLT),
                ui.stat("Workouts", len(me.get("workouts", [])), ui.C.text, ft.Icons.FITNESS_CENTER),
                ui.stat("Gold", int(me.get("goldBalance") or 0), ui.C.gold, ft.Icons.PAID_OUTLINED)], spacing=10),
        ui.section("Attributes"), _attributes(p),
        *([ui.section("Body"), ui.card(ft.Row([ft.Column([ui.label(k, size=11), ft.Text(str(v), color=ui.C.text)], spacing=2)
                                            for k, v in body_stats], alignment=ft.MainAxisAlignment.SPACE_AROUND))] if body_stats else []),
        *links,
        actions=[ui.button("Edit", lambda e: edit_dialog(app), icon=ft.Icons.EDIT_OUTLINED, kind="ghost")],
    )


def public(app, user_id: str) -> ft.Control:
    from views import social
    box = ft.Column([ui.loading()], spacing=14)

    def load():
        try:
            res = app.api.call("get-user-profile", params={"user_id": user_id})
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        p = res["profile"]
        status = res.get("friendshipStatus")
        if status == "accepted":
            action = ui.button("Message", lambda e: app.open(social.dm, {"id": p["id"], "username": p["username"]}),
                               icon=ft.Icons.CHAT_OUTLINED)
        elif status in ("pending_outgoing", "pending", "requested"):
            action = ui.body("Friend request sent", color=ui.C.accent)
        elif status == "pending_incoming":
            action = ui.button("Respond in Friends", lambda e: social.open_tab(app, "friends"), kind="accent")
        else:
            action = ui.button("Add friend", lambda e: add_friend(p), icon=ft.Icons.PERSON_ADD)
        recent = res.get("recentWorkouts") or []
        box.controls = [
            _header(p, res.get("levelInfo") or {}, ui.C.primary_bright),
            ft.Row([action, ui.button("Report", lambda e: social.report_dialog(app, p["id"], p["username"]),
                                      icon=ft.Icons.FLAG_OUTLINED, kind="text")], wrap=True),
            ui.section("Attributes"), _attributes(p),
            ui.section("Recent workouts"),
            ui.card(ft.Column([ft.Row([ft.Text(workout_line(w), color=ui.C.text, expand=True),
                                       ft.Text(f"+{w.get('xp_earned') or 0} XP", color=ui.C.primary_bright)])
                               for w in recent[:8]], spacing=10) if recent else ui.empty("No workouts yet.")),
        ]
        app.page.update()

    def add_friend(p):
        def work():
            try:
                app.api.call("send-friend-request", "POST", {"addressee_id": p["id"]})
                app.toast(f"Friend request sent to {p['username']}.")
            except ApiError as ex:
                app.toast(str(ex), error=True)
            load()
        app.run(work)

    app.run(load)
    return ui.screen("Profile", box)
