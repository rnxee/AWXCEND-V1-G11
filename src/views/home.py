"""Dashboard: level + rank hero, stats, quick actions, recent workouts."""
from datetime import datetime, timedelta, timezone

import flet as ft

import ui
from api import ApiError
from views.train import EXERCISES

NAMES = dict(EXERCISES)


def _streak(me: dict) -> int:
    s = me.get("streak")
    if isinstance(s, dict):
        return int(s.get("current_streak") or 0)
    return int(me["profile"].get("streak") or 0)


def workout_line(w: dict) -> str:
    ex = w.get("exercise") or ""
    name = NAMES.get(ex) or ex.replace("_", " ").title()
    if w.get("duration_seconds"):
        s = int(w["duration_seconds"])
        return f"{name} · {s // 60}:{s % 60:02d}"  # a 45 s plank is "0:45", not "1 min"
    if not w.get("reps"):  # public profiles don't send a timed set's duration: show the exercise alone
        return name
    parts = [name, f"{w.get('sets') or 1}×{w['reps']}"]
    if w.get("weight_kg"):
        parts.append(f"{w['weight_kg']:g} kg")
    return " · ".join(parts)


def deletable(w: dict, now: datetime | None = None) -> bool:
    """What delete-workout accepts: a hand-logged workout from the last 24 hours (the server also
    refuses mission/dungeon sets and anything from before a path change, and says why)."""
    if w.get("workout_source") != "manual" or not w.get("id"):
        return False
    try:
        t = datetime.fromisoformat((w.get("logged_at") or "").replace("Z", "+00:00"))
    except ValueError:
        return False
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)  # workout_logs.logged_at is UTC without saying so
    return (now or datetime.now(timezone.utc)) - t < timedelta(hours=24)


def confirm_delete_workout(app, w: dict, after) -> None:
    def go(e):
        app.close_dialog()

        def work():
            try:
                res = app.api.call("delete-workout", "POST", {"workout_log_id": w["id"]})
                app.load_me()
            except ApiError as ex:
                app.toast(str(ex), error=True)
                return
            app.toast(f"Workout deleted · −{res.get('xp_removed', 0)} XP")
            after()
        app.run(work)
    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text("Delete this workout?"),
        content=ft.Text(f"{workout_line(w)}\nThe {w.get('xp_earned') or 0} XP it earned is taken back."),
        actions=[ui.button("Keep", lambda e: app.close_dialog(), kind="text"),
                 ui.button("Delete", go, kind="danger")]))


def view(app) -> ft.Control:
    me, p = app.me, app.me["profile"]
    lvl = me.get("levelInfo") or {}
    need = lvl.get("xpForNextLevel") or 1
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    this_week = sum(1 for w in me.get("workouts", [])
                    if (w.get("logged_at") or "") >= week_ago.isoformat()[:19])

    level = lvl.get("level", 1)
    hero = ui.card(ft.Column([
        ft.Row([ui.diamond(ui.C.primary_bright, 7), ui.label("Status window", ui.C.primary_bright, 11)], spacing=8),
        ft.Row([
            ui.avatar(p.get("username", "?"), 60, ui.C.accent),
            ft.Column([ui.body("Welcome back,", size=12),
                       ui.heading(p.get("username", ""), 20),
                       ft.Row([ui.tag(ui.rank_text(p), ui.C.gold),
                               ui.tag(ui.FOCUS_LABEL.get(p.get("focus_type"), "Hybrid Athlete"), ui.C.accent)],
                              spacing=6, wrap=True)],
                      spacing=4, expand=True),
            ft.Column([ui.label("Level", ui.C.dim, 10), ui.num(level, 40, ui.C.primary_bright)],
                      horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=0),
        ], vertical_alignment=ft.CrossAxisAlignment.CENTER),
        ui.xp_bar((lvl.get("xpIntoLevel") or 0) / need, height=12),
        ft.Row([ui.body(f"{lvl.get('xpIntoLevel', 0):,} / {need:,} XP", ui.C.text, 12),
                ui.body(f"{lvl.get('xpToNextLevel', 0):,} XP to level {level + 1}", size=12)],
               alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
    ], spacing=12), padding=18)

    stats = ft.Row([
        ui.stat("Total XP", int(p.get("xp") or 0), ui.C.primary_bright, ft.Icons.BOLT),
        ui.stat("Streak", f"{_streak(me)} d", ui.C.gold, ft.Icons.LOCAL_FIRE_DEPARTMENT),
        ui.stat("This week", this_week, ui.C.food, ft.Icons.FITNESS_CENTER),
    ], spacing=10)

    def action(text, icon, color, on_click):
        return ui.card(ft.Column([ui.icon_chip(icon, color, 40),
                                  ft.Text(text, size=12, color=ui.C.text, font_family="LatoBold",
                                          text_align=ft.TextAlign.CENTER)],
                                 horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                 alignment=ft.MainAxisAlignment.CENTER, spacing=8),
                       padding=10, on_click=on_click, col={"xs": 4, "md": 2.4}, height=104,
                       alignment=ft.Alignment.CENTER, accent=color)

    from views import coach, social, train  # local: avoids import cycles between screens
    actions = ft.ResponsiveRow([
        action("Log workout", ft.Icons.EDIT_NOTE, ui.C.primary, lambda e: app.go("train")),
        action("Camera", ft.Icons.CAMERA_ALT_OUTLINED, ui.C.camera, lambda e: train.open_camera(app)),
        action("Log meal", ft.Icons.RESTAURANT, ui.C.food, lambda e: app.go("food")),
        action("AI coach", ft.Icons.AUTO_AWESOME, ui.C.accent, lambda e: app.open(coach.view)),
        action("Leaderboard", ft.Icons.LEADERBOARD, ui.C.gold, lambda e: app.open(social.leaderboard)),
    ], spacing=10, run_spacing=10)

    recent = me.get("workouts", [])[:6]
    recent_list = ft.Column([
        ft.Row([ft.Icon(ft.Icons.CAMERA_ALT if w.get("workout_source") == "camera" else ft.Icons.FITNESS_CENTER,
                        color=ui.C.dim, size=18),
                ft.Text(workout_line(w), expand=True, color=ui.C.text),
                ft.Column([ft.Text(f"+{w.get('xp_earned') or 0} XP", color=ui.C.primary_bright, font_family="LatoBold"),
                           ui.body(ui.when(w.get("logged_at", "")), size=11)],
                          horizontal_alignment=ft.CrossAxisAlignment.END, spacing=0),
                *([ft.IconButton(ft.Icons.DELETE_OUTLINE, icon_color=ui.C.dim, tooltip="Delete workout",
                                 on_click=lambda e, w=w: confirm_delete_workout(app, w, lambda: app.go("home")))]
                  if deletable(w) else [])])
        for w in recent
    ], spacing=12) if recent else ui.empty("No workouts yet. Log your first one!", ft.Icons.FITNESS_CENTER)

    def refresh(e=None):
        def work():
            try:
                app.load_me()
            except ApiError as ex:
                app.toast(str(ex), error=True)
                return
            app.go("home")
        app.run(work)

    def show_again(e):
        from views.account import set_active
        set_active(app, True, lambda: app.go("home"))

    friend_note = [ui.card(ft.Row([ft.Icon(ft.Icons.VISIBILITY_OFF, color=ui.C.gold),
                                   ft.Text("Your account is hidden.", expand=True),
                                   ui.button("Show it again", show_again, kind="text")]),
                           accent=ui.fade(ui.C.gold, 0x88))] if p.get("deactivated_at") else []
    friend_note += [ui.card(ft.Row([ft.Icon(ft.Icons.GAVEL, color=ui.C.danger),
                                    ft.Text(r.get("message", ""), color=ui.C.text, expand=True)]),
                            accent=ui.fade(ui.C.danger, 0x88)) for r in me.get("restrictions") or []]
    if me.get("pendingFriendRequests"):
        n = me["pendingFriendRequests"]
        friend_note += [ui.card(ft.Row([ft.Icon(ft.Icons.PERSON_ADD, color=ui.C.accent),
                                       ft.Text(f"{n} friend request{'s' if n > 1 else ''} waiting", expand=True),
                                       ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim)]),
                               on_click=lambda e: social.open_tab(app, "friends"), accent=ui.fade(ui.C.accent, 0x66))]

    return ui.screen(
        "Dashboard", hero, stats, *friend_note,
        ui.section("Quick actions"), actions,
        ui.section("Recent workouts"), ui.card(recent_list),
        actions=[ft.IconButton(ft.Icons.REFRESH, on_click=refresh, tooltip="Refresh")],
    )
