"""Admin / moderator panel: user reports, post moderation queue, user roles.
Visibility here is a convenience only - every action is permission-checked by the server."""
import flet as ft

import ui
from api import ApiError

ROLES = [("user", "User"), ("moderator", "Moderator"), ("admin", "Admin")]


def _act(app, fn: str, body: dict, ok: str, reload) -> None:
    def work():
        try:
            app.api.call(fn, "POST", body)
            app.toast(ok)
        except ApiError as ex:
            app.toast(str(ex), error=True)
        reload()
    app.run(work)


def reports(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)

    def load():
        try:
            items = app.api.call("get-reports", params={"status": "pending"}).get("reports", [])
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        box.controls = [card(r) for r in items] or [ui.empty("No open reports.", ft.Icons.VERIFIED_OUTLINED)]
        app.page.update()

    def card(r):
        reported, reporter = r.get("reported") or {}, r.get("reporter") or {}
        parts = [ft.Row([ft.Icon(ft.Icons.FLAG, color=ui.C.danger, size=18),
                         ft.Text(f"{reported.get('username', 'deleted user')}", color=ui.C.text, font_family="LatoBold", expand=True),
                         ui.body(ui.when(r.get("created_at")), size=11)]),
                 ui.body(f"{r.get('reason', '').replace('_', ' ').title()} · reported by {reporter.get('username', 'deleted user')}", size=12)]
        if r.get("context_excerpt"):
            parts.append(ui.card(ft.Text(f"“{r['context_excerpt']}”", color=ui.C.dim, italic=True), padding=10))
        if r.get("details"):
            parts.append(ft.Text(r["details"], color=ui.C.text))
        parts.append(ft.Row([
            ui.button("Dismiss", lambda e: _act(app, "resolve-report", {"report_id": r["id"], "status": "dismissed"},
                                                "Report dismissed.", load), kind="ghost"),
            ui.button("Mark reviewed", lambda e: _act(app, "resolve-report", {"report_id": r["id"], "status": "reviewed"},
                                                      "Report marked reviewed.", load)),
        ], alignment=ft.MainAxisAlignment.END, wrap=True))
        return ui.card(ft.Column(parts, spacing=8), accent=ui.fade(ui.C.danger, 0x55))

    app.run(load)
    return box


def posts(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)

    def load():
        try:
            items = app.api.call("get-pending-posts").get("posts", [])
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        box.controls = [ui.card(ft.Column([
            ft.Row([ft.Text((p.get("users") or {}).get("username", ""), color=ui.C.text, font_family="LatoBold", expand=True),
                    ui.body(f"{p.get('tab', '')} · {ui.when(p.get('created_at'))}", size=11)]),
            *([ui.heading(p["title"], 15)] if p.get("title") else []),
            ft.Text(p.get("content", ""), color=ui.C.text),
            *([ft.Image(src=p["image_url"], height=200, border_radius=10)] if p.get("image_url") else []),
            ft.Row([ui.button("Reject", lambda e, p=p: _act(app, "moderate-post", {"post_id": p["id"], "status": "rejected"}, "Post rejected.", load), kind="danger"),
                    ui.button("Approve", lambda e, p=p: _act(app, "moderate-post", {"post_id": p["id"], "status": "approved"}, "Post approved.", load))],
                   alignment=ft.MainAxisAlignment.END),
        ], spacing=8)) for p in items] or [ui.empty("No posts waiting for review.", ft.Icons.TASK_ALT)]
        app.page.update()

    app.run(load)
    return box


def users(app) -> ft.Control:
    box = ft.Column(spacing=10)
    search = ui.field("Search users", prefix_icon=ft.Icons.SEARCH, expand=True)
    is_admin = app.me["profile"].get("role") == "admin"

    def load(q=""):
        try:
            items = app.api.call("list-users", params={"query": q}).get("users", [])
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex))]
            app.page.update()
            return
        box.controls = [row(u) for u in items] or [ui.empty("No users found.")]
        app.page.update()

    def row(u):
        mine = u["id"] == app.api.user_id
        right = (ui.dropdown("Role", ROLES, u.get("role", "user"), width=160,
                             on_select=lambda e, u=u: _act(app, "update-user-role", {"user_id": u["id"], "role": e.control.value},
                                                           f"{u['username']} is now {e.control.value}.", lambda: load(search.value.strip())))
                 if is_admin and not mine else ui.body((u.get("role") or "user").title()))
        return ui.card(ft.Row([ui.avatar(u.get("username", "?"), 34),
                               ft.Column([ft.Text(u.get("username", ""), color=ui.C.text, font_family="LatoBold"),
                                          ui.body(f"{u.get('rank') or 'Unranked'} · joined {ui.when(u.get('created_at'))[:6]}", size=12)],
                                         spacing=0, expand=True), right]), padding=10)

    search.on_submit = lambda e: app.run(load, search.value.strip())
    app.run(load)
    return ft.Column([ft.Row([search]), box], spacing=12)


SECTIONS = [("reports", "Reports"), ("posts", "Post queue"), ("users", "Users")]
BUILDERS = {"reports": reports, "posts": posts, "users": users}


def view(app) -> ft.Control:
    holder = ft.Container(reports(app))

    def switch(key):
        holder.content = BUILDERS[key](app)
        app.page.update()

    return ui.screen("Admin panel", ui.chips(SECTIONS, "reports", switch), holder,
                     subtitle=f"Signed in as {app.me['profile'].get('role')}.")
