"""Dashboard: level + rank hero, stats, quick actions, recent workouts."""
from datetime import datetime, timedelta, timezone

import flet as ft

import ui
from api import ApiError


def _streak(me: dict) -> int:
    s = me.get("streak")
    if isinstance(s, dict):
        return int(s.get("current_streak") or 0)
    return int(me["profile"].get("streak") or 0)


def workout_line(w: dict) -> str:
    name = (w.get("exercise") or "").replace("_", " ").title()
    if w.get("duration_seconds"):
        return f"{name} · {round(w['duration_seconds'] / 60)} min"
    parts = [name, f"{w.get('sets') or 1}×{w.get('reps') or 0}"]
    if w.get("weight_kg"):
        parts.append(f"{w['weight_kg']:g} kg")
    return " · ".join(parts)


def view(app) -> ft.Control:
    me, p = app.me, app.me["profile"]
    lvl = me.get("levelInfo") or {}
    need = lvl.get("xpForNextLevel") or 1
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    this_week = sum(1 for w in me.get("workouts", [])
                    if (w.get("logged_at") or "") >= week_ago.isoformat()[:19])

    hero = ui.card(ft.Column([
        ft.Row([
            ui.avatar(p.get("username", "?"), 52, ui.C.accent),
            ft.Column([ui.heading(f"Welcome back, {p.get('username', '')}", 18),
                       ui.body(f"{ui.rank_text(p)} · {ui.FOCUS_LABEL.get(p.get('focus_type'), '')}", color=ui.C.accent)],
                      spacing=2, expand=True),
            ft.Column([ui.label("Level", size=11), ui.num(lvl.get("level", 1), 30, ui.C.primary_bright)],
                      horizontal_alignment=ft.CrossAxisAlignment.END, spacing=0),
        ]),
        ui.xp_bar((lvl.get("xpIntoLevel") or 0) / need),
        ui.body(f"{lvl.get('xpToNextLevel', 0):,} XP to level {lvl.get('level', 1) + 1}", size=12),
    ], spacing=10), padding=18, accent=ui.fade(ui.C.primary, 0x66))

    stats = ft.Row([
        ui.stat("Total XP", int(p.get("xp") or 0), ui.C.primary_bright, ft.Icons.BOLT),
        ui.stat("Streak", f"{_streak(me)} d", ui.C.gold, ft.Icons.LOCAL_FIRE_DEPARTMENT),
        ui.stat("This week", this_week, ui.C.food, ft.Icons.FITNESS_CENTER),
    ], spacing=10)

    def action(text, icon, color, on_click):
        return ui.card(ft.Column([ft.Icon(icon, color=color, size=26), ui.body(text, ui.C.text, 13, text_align=ft.TextAlign.CENTER)],
                                 horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=6),
                       padding=12, on_click=on_click, col={"xs": 4, "md": 2.4}, height=88,
                       alignment=ft.Alignment.CENTER)

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
                          horizontal_alignment=ft.CrossAxisAlignment.END, spacing=0)])
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

    friend_note = []
    if me.get("pendingFriendRequests"):
        n = me["pendingFriendRequests"]
        friend_note = [ui.card(ft.Row([ft.Icon(ft.Icons.PERSON_ADD, color=ui.C.accent),
                                       ft.Text(f"{n} friend request{'s' if n > 1 else ''} waiting", expand=True),
                                       ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim)]),
                               on_click=lambda e: social.open_tab(app, "friends"), accent=ui.fade(ui.C.accent, 0x66))]

    return ui.screen(
        "Dashboard", hero, stats, *friend_note,
        ui.label("Quick actions"), actions,
        ui.label("Recent workouts"), ui.card(recent_list),
        actions=[ft.IconButton(ft.Icons.REFRESH, on_click=refresh, tooltip="Refresh")],
    )
