"""Moderation sanctions (moderators and admins): ban an account, or restrict some of its privileges,
for a while or for good. The server decides who may sanction whom and enforces every sanction."""
import flet as ft

import ui
from api import ApiError

PRIVILEGES = [("post", "Posting"), ("chat", "Community chat"), ("dm", "Direct messages"),
              ("friend_request", "Friend requests"), ("report", "Reporting")]
DURATIONS = [("1h", "1 hour"), ("1d", "1 day"), ("7d", "7 days"), ("30d", "30 days"), ("1y", "1 year"),
             ("forever", "Permanent")]
UNITS = {"h": "hours", "d": "days", "y": "years"}
SYNC_WARNING = " But the sign-in block didn't update - ask the project owner to check the user in Supabase Auth."


def duration_body(key: str) -> dict:
    """A DURATIONS key -> the sanctions function's duration fields."""
    if key == "forever":
        return {"permanent": True}
    return {"amount": int(key[:-1]), "unit": UNITS[key[-1]]}


def preview(kind: str, privileges: list[str], key: str, reason: str) -> str:
    """Roughly what the player will read (the server writes the exact text, with the end date)."""
    span = "permanently" if key == "forever" else f"for {dict(DURATIONS)[key]}"
    why = reason.strip() or "…"
    if kind == "ban":
        return f"Account suspended {span}. Reason: {why}"
    names = ", ".join(dict(PRIVILEGES)[p].lower() for p in privileges) or "…"
    return f"You can't use {names} {span}. Reason: {why}"


def issue_dialog(app, user: dict, report_id: str | None = None, on_done=None) -> None:
    state = {"kind": "restrict", "span": "1d"}
    boxes = {k: ft.Checkbox(label=label, value=k == "chat") for k, label in PRIVILEGES}
    privilege_box = ft.Column(list(boxes.values()), spacing=0)
    reason = ui.field("Reason (they see it)", multiline=True, max_lines=3, max_length=500)
    shown = ui.body("", size=12, color=ui.C.gold)
    error = ft.Text("", color=ui.C.danger, visible=False)

    def chosen():
        return [k for k, b in boxes.items() if b.value]

    def refresh(e=None):
        error.visible = False  # a fixed form shouldn't keep the old complaint
        privilege_box.visible = state["kind"] == "restrict"
        shown.value = "They'll see: " + preview(state["kind"], chosen(), state["span"], reason.value or "")
        app.page.update()

    for b in boxes.values():
        b.on_change = refresh
    reason.on_change = refresh

    def issue(e):
        if not (reason.value or "").strip():
            error.value, error.visible = "Write the reason - the player reads it.", True
            app.page.update()
            return
        if state["kind"] == "restrict" and not chosen():
            error.value, error.visible = "Pick at least one privilege to restrict.", True
            app.page.update()
            return
        body = {"action": "issue", "user_id": user["id"], "kind": state["kind"], "privileges": chosen(),
                "reason": reason.value.strip(), **duration_body(state["span"]),
                **({"report_id": report_id} if report_id else {})}
        app.close_dialog()

        def work():
            try:
                res = app.api.call("sanctions", "POST", body)
                app.toast(f"{user.get('username', 'Player')} is {'suspended' if state['kind'] == 'ban' else 'restricted'}."
                          + ("" if res.get("auth_synced", True) else SYNC_WARNING))
            except ApiError as ex:
                app.toast(str(ex), error=True)
            if on_done:
                on_done()
        app.run(work)

    refresh_text = preview(state["kind"], chosen(), state["span"], "")
    shown.value = "They'll see: " + refresh_text
    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text(f"Sanction {user.get('username', 'player')}"), scrollable=True,
        content=ft.Column([
            ui.chips([("restrict", "Restrict"), ("ban", "Ban account")], "restrict",
                     lambda k: (state.update(kind=k), refresh())),
            privilege_box,
            ui.label("For how long"),
            ui.chips(DURATIONS, "1d", lambda k: (state.update(span=k), refresh())),
            reason, shown, error,
        ], tight=True, spacing=12, width=460),
        actions=[ui.button("Cancel", lambda e: app.close_dialog(), kind="text"),
                 ui.button("Apply", issue, kind="danger")]))


def section(app) -> ft.Control:
    """Admin panel tab: find a player to sanction, and the sanctions in force (with Lift)."""
    active = ft.Column([ui.loading()], spacing=10)
    found = ft.Column(spacing=8)
    search = ui.field("Find a player to sanction", prefix_icon=ft.Icons.PERSON_SEARCH, expand=True)
    is_admin = app.me["profile"].get("role") == "admin"

    def load():
        try:
            items = app.api.call("sanctions", params={"view": "active"}).get("sanctions", [])
        except ApiError as ex:
            active.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        active.controls = [card(s) for s in items] or [ui.empty("No sanctions in force.", ft.Icons.GAVEL)]
        app.page.update()

    def card(s):
        player = (s.get("player") or {}).get("username", "deleted user")
        issuer = (s.get("issuer") or {}).get("username", "deleted user")
        return ui.card(ft.Column([
            ft.Row([ui.tag("ban" if s["kind"] == "ban" else "restricted", ui.C.danger if s["kind"] == "ban" else ui.C.gold),
                    ft.Text(player, color=ui.C.text, font_family="LatoBold", expand=True),
                    ui.body(ui.when(s.get("created_at")).split(",")[0], size=11)]),
            ui.body(s.get("message", ""), color=ui.C.text, size=13),
            ui.body(f"by {issuer} ({s.get('issued_by_role')})", size=11),
            *([ft.Row([ui.button("Lift", lambda e, s=s: lift(s), kind="ghost")], alignment=ft.MainAxisAlignment.END)]
              if s.get("issued_by_role") != "admin" or is_admin else []),  # only an admin lifts an admin's
        ], spacing=6), padding=12, accent=ui.fade(ui.C.danger, 0x55))

    def lift(s):
        note = ui.field("Note (optional)", max_length=500)

        def go(e):
            app.close_dialog()

            def work():
                try:
                    res = app.api.call("sanctions", "POST", {"action": "lift", "sanction_id": s["id"], "note": note.value.strip()})
                    app.toast("Sanction lifted." + ("" if res.get("auth_synced", True) else SYNC_WARNING))
                except ApiError as ex:
                    app.toast(str(ex), error=True)
                load()
            app.run(work)
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text(f"Lift this sanction on {(s.get('player') or {}).get('username', 'the player')}?"),
            content=ft.Column([ui.body(s.get("message", "")), note], tight=True, spacing=10, width=420),
            actions=[ui.button("Cancel", lambda e: app.close_dialog(), kind="text"), ui.button("Lift", go)]))

    def find(e=None):
        q = search.value.strip()
        if len(q) < 2:
            return
        found.controls = [ui.loading("Searching...")]
        app.page.update()

        def work():
            try:
                users = app.api.call("sanctions", params={"query": q}).get("users", [])
            except ApiError as ex:
                found.controls = [ui.error_box(str(ex))]
                app.page.update()
                return
            found.controls = [ui.card(ft.Row([
                ui.avatar(u.get("username", "?"), 32),
                ft.Column([ft.Text(u.get("username", ""), color=ui.C.text, font_family="LatoBold"),
                           ui.body(f"{(u.get('role') or 'user').title()} · {u.get('rank') or 'Unranked'}", size=12)],
                          spacing=0, expand=True),
                ui.button("Sanction", lambda e, u=u: issue_dialog(app, u, on_done=lambda: app.run(load)), kind="danger"),
            ]), padding=10) for u in users] or [ui.empty(f"Nobody called “{q}”.", ft.Icons.SEARCH_OFF)]
            app.page.update()
        app.run(work)

    search.on_submit = find
    app.run(load)
    return ft.Column([ft.Row([search, ft.IconButton(ft.Icons.SEARCH, on_click=find, tooltip="Search")]), found,
                      ui.section("In force"), active], spacing=12)
