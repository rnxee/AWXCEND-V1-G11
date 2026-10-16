"""Admin / moderator panel: user reports, post moderation queue, user roles.
Visibility here is a convenience only - every action is permission-checked by the server."""
import flet as ft

import ui
from api import ApiError
from views import sanctions

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
        from views.social import open_profile
        name = ft.Text(f"{reported.get('username', 'deleted user')}", color=ui.C.text, font_family="LatoBold")
        parts = [ft.Row([ft.Icon(ft.Icons.FLAG, color=ui.C.danger, size=18),
                         ft.Container(name, expand=True, tooltip="View profile" if reported.get("id") else None,
                                      on_click=(lambda e: open_profile(app, reported["id"])) if reported.get("id") else None),
                         ui.body(ui.when(r.get("created_at")), size=11)]),
                 ui.body(f"{r.get('reason', '').replace('_', ' ').title()} · reported by {reporter.get('username', 'deleted user')}", size=12)]
        if r.get("context_excerpt"):
            parts.append(ft.Container(ft.Text(f"“{r['context_excerpt']}”", color=ui.C.dim, italic=True),
                                      padding=ft.Padding.only(left=12, top=4, bottom=4),
                                      border=ft.Border(left=ft.BorderSide(2, ui.fade(ui.C.danger, 0x99)))))
        if r.get("details"):
            parts.append(ft.Text(r["details"], color=ui.C.text))
        parts.append(ft.Row([
            *([ui.button("Sanction", lambda e: sanctions.issue_dialog(app, reported, r["id"], lambda: app.run(load)),
                         kind="danger")] if reported.get("id") else []),
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

    def confirm_role(u, role):
        def go(e):
            app.close_dialog()
            _act(app, "update-user-role", {"user_id": u["id"], "role": role}, f"{u['username']} is now {role}.",
                 lambda: load(search.value.strip()))

        def cancel(e):
            app.close_dialog()
            app.run(load, search.value.strip())  # put the picker back to the current role
        app.page.show_dialog(ft.AlertDialog(
            modal=True,  # only the buttons close it, so Cancel always puts the picker back
            title=ft.Text(f"Make {u['username']} {'an' if role == 'admin' else 'a'} {role}?"),
            content=ft.Text({"admin": "Admins can change anyone's role and see the audit log.",
                             "moderator": "Moderators review reports, bugs and the post queue.",
                             "user": "They lose access to the admin panel."}[role]),
            actions=[ui.button("Cancel", cancel, kind="text"), ui.button("Change role", go)]))

    def row(u):
        mine = u["id"] == app.api.user_id
        right = (ui.dropdown("Role", ROLES, u.get("role", "user"), width=160,
                             on_select=lambda e, u=u: confirm_role(u, e.control.value))
                 if is_admin and not mine else ui.body("You" if mine else (u.get("role") or "user").title()))
        return ui.card(ft.Row([ui.avatar(u.get("username", "?"), 34),
                               ft.Column([ft.Text(u.get("username", ""), color=ui.C.text, font_family="LatoBold"),
                                          ui.body(f"{u.get('rank') or 'Unranked'} · joined {ui.when(u.get('created_at')).split(',')[0]}", size=12)],
                                         spacing=0, expand=True), right]), padding=10)

    search.on_submit = lambda e: app.run(load, search.value.strip())
    app.run(load)
    return ft.Column([ft.Row([search]), box], spacing=12)


def bugs(app) -> ft.Control:
    """Problems players reported about the app itself (Report a problem in Account)."""
    box = ft.Column([ui.loading()], spacing=10)
    labels = {"bug": "Bug", "feature_request": "Idea", "other": "Other"}

    def load():
        try:
            items = app.api.call("get-bug-reports", params={"status": "open"}).get("reports", [])
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        box.controls = [ui.card(ft.Column([
            ft.Row([ui.tag(labels.get(b.get("category"), "Other"), ui.C.gold),
                    ft.Text((b.get("reporter") or {}).get("username", "deleted user"), color=ui.C.text,
                            font_family="LatoBold", expand=True),
                    ui.body(ui.when(b.get("created_at")), size=11)]),
            ft.Text(b.get("description", ""), color=ui.C.text, selectable=True),
            ft.Row([ui.button("Dismiss", lambda e, b=b: _act(app, "resolve-bug-report", {"report_id": b["id"], "status": "dismissed"},
                                                             "Dismissed.", load), kind="ghost"),
                    ui.button("Resolved", lambda e, b=b: _act(app, "resolve-bug-report", {"report_id": b["id"], "status": "resolved"},
                                                              "Marked resolved.", load))],
                   alignment=ft.MainAxisAlignment.END, wrap=True),
        ], spacing=8), accent=ui.fade(ui.C.gold, 0x55)) for b in items] or [ui.empty("No open problem reports.", ft.Icons.BUG_REPORT_OUTLINED)]
        app.page.update()

    app.run(load)
    return box


def audit(app) -> ft.Control:
    """Append-only record of every moderation and role change (admins only)."""
    box = ft.Column([ui.loading()], spacing=8)
    entries: list[dict] = []

    def older(e):
        more.disabled = True  # one page at a time: a double tap would fetch (and show) the same page twice
        app.page.update()
        app.run(load, entries[-1]["created_at"] if entries else None)

    more = ui.button("Load older", older, kind="text", visible=False)

    def load(before=None):
        try:
            page = app.api.call("admin-audit-log", params={"limit": 50, **({"before": before} if before else {})}
                                ).get("entries", [])
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load, before))]  # retry the same page
            more.disabled = False
            app.page.update()
            return
        if before is None:
            entries.clear()
        entries.extend(page)
        more.disabled = False
        more.visible = len(page) == 50
        box.controls = [ui.card(ft.Column([
            ft.Row([ft.Text(a.get("action", ""), color=ui.C.text, font_family="LatoBold", expand=True),
                    ui.body(ui.when(a.get("created_at")), size=11)]),
            ui.body(f"by {a.get('actor_username') or 'deleted user'} ({a.get('actor_role') or '?'}) · "
                    f"{a.get('target_type', '')}" + "".join(f" · {k.replace('_', ' ')}: {v}"
                                                            for k, v in (a.get("metadata") or {}).items()), size=12),
        ], spacing=2), padding=10) for a in entries] or [ui.empty("Nothing recorded yet.", ft.Icons.HISTORY)]
        app.page.update()

    app.run(load)
    return ft.Column([box, more], spacing=8)


# Who sees which section. UI only: the server re-checks every action (_shared/permissions.ts).
STAFF, ADMIN = ("moderator", "admin"), ("admin",)
SECTIONS = [("reports", "Reports", STAFF), ("posts", "Post queue", STAFF), ("bugs", "Bugs", STAFF),
            ("sanctions", "Sanctions", STAFF), ("users", "Users", ADMIN), ("audit", "Audit log", ADMIN)]
BUILDERS = {"reports": reports, "posts": posts, "bugs": bugs, "sanctions": sanctions.section, "users": users,
            "audit": audit}


def view(app) -> ft.Control:
    holder = ft.Container(reports(app))
    role = app.me["profile"].get("role")
    sections = [(k, label) for k, label, roles in SECTIONS if role in roles]

    def switch(key):
        holder.content = BUILDERS[key](app)
        app.page.update()

    return ui.screen("Admin panel", ui.chips(sections, "reports", switch), holder,
                     subtitle=f"Signed in as {app.me['profile'].get('role')}.")
