"""Social tab: Gymunnity feed + community chat, friends, direct messages, leaderboard."""
import base64
import threading

import flet as ft

import ui
from api import ApiError

REPORT_REASONS = [("harassment", "Harassment or bullying"), ("spam", "Spam"), ("impersonation", "Impersonation"),
                  ("inappropriate_content", "Inappropriate content"), ("cheating", "Cheating / faking stats"),
                  ("other", "Other")]
MAX_IMAGE = 1_900_000  # create-post takes JPEGs up to ~2 MB


def prepare_jpeg(data: bytes, name: str) -> bytes | None:
    """Downscale/re-encode a picked photo to a JPEG under the upload limit (OpenCV on desktop)."""
    try:
        import cv2
        import numpy as np
    except ImportError:  # phone build: accept JPEGs that already fit
        return data if name.lower().endswith((".jpg", ".jpeg")) and len(data) <= MAX_IMAGE else None
    img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return None
    scale = 1280 / max(img.shape[:2])
    if scale < 1:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    for quality in (85, 75, 60, 45):
        ok, jpg = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if ok and len(jpg) <= MAX_IMAGE:
            return jpg.tobytes()
    return None


# ---- shared bits ----------------------------------------------------------------
def open_profile(app, user_id: str) -> None:
    from views import profile
    if user_id == app.api.user_id:
        app.go("profile")
    else:
        app.open(profile.public, user_id)


def report_dialog(app, user_id: str, username: str, message: dict | None = None, kind: str | None = None) -> None:
    reason = {"v": None}
    details = ui.field("Details (optional)", multiline=True, min_lines=2, max_lines=4, max_length=500)

    def send(e):
        if not reason["v"]:
            app.toast("Pick a reason.", error=True)
            return
        body = {"reported_user_id": user_id, "reason": reason["v"], "details": details.value.strip()}
        if message:
            body.update(message_type=kind, message_id=message["id"])
        app.page.pop_dialog()

        def work():
            try:
                app.api.call("report-user", "POST", body)
                app.toast("Report sent. A moderator will review it.")
            except ApiError as ex:
                app.toast(str(ex), error=True)
        app.run(work)

    quote = [ui.card(ft.Text(message.get("message", ""), color=ui.C.dim, italic=True), padding=10)] if message else []
    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text(f"Report {'message from ' if message else ''}{username}"),
        content=ft.Column([*quote, ui.label("Reason"),
                           ui.chips(REPORT_REASONS, "", lambda k: reason.update(v=k)), details],
                          tight=True, spacing=10, width=440, scroll=ft.ScrollMode.AUTO),
        actions=[ui.button("Cancel", lambda e: app.page.pop_dialog(), kind="text"),
                 ui.button("Send report", send, kind="danger")]))


def chat_panel(app, fetch, send, bubble, poll_s: float, hint: str) -> ft.Control:
    """Messages newest at the bottom, 'Load older' paging, polling for new ones, and a composer.
    fetch(before) -> (messages oldest-first, has_more); send(text); bubble(msg) -> control."""
    msgs: list[dict] = []
    state = {"has_more": False}
    stop = threading.Event()
    lv = ft.ListView(expand=True, spacing=8, auto_scroll=True, padding=ft.Padding.symmetric(vertical=8))
    older = ui.button("Load older messages", lambda e: app.run(load_older), kind="text", visible=False)
    box = ui.field(hint, expand=True, max_length=500, on_submit=lambda e: submit())

    def render():
        lv.controls = [bubble(m) for m in msgs] or [ui.empty("No messages yet. Say hi!", ft.Icons.CHAT_BUBBLE_OUTLINE)]
        older.visible = state["has_more"]
        try:
            app.page.update()
        except Exception:  # screen already left
            stop.set()

    def merge(new: list[dict], front: bool = False):
        seen = {m["id"] for m in msgs}
        fresh = [m for m in new if m["id"] not in seen]
        if front:
            msgs[:0] = fresh
        else:
            msgs.extend(fresh)
        return bool(fresh)

    def load_older():
        try:
            page, state["has_more"] = fetch(msgs[0]["created_at"] if msgs else None)
        except ApiError as ex:
            app.toast(str(ex), error=True)
            return
        lv.auto_scroll = False
        merge(page, front=True)
        render()

    def poll():
        first = True
        while not stop.is_set():
            try:
                page, more = fetch(None)
                if first:
                    state["has_more"] = more
                if merge(page) or first:
                    lv.auto_scroll = True
                    render()
                first = False
            except ApiError as ex:
                if first:
                    lv.controls = [ui.error_box(str(ex))]
                    render()
                    return
            stop.wait(poll_s)

    def submit():
        text = box.value.strip()
        if not text:
            return
        box.value = ""
        app.page.update()

        def work():
            try:
                send(text)
                page, _ = fetch(None)
                lv.auto_scroll = True
                merge(page)
                render()
            except ApiError as ex:
                box.value = text
                app.toast(str(ex), error=True)
                app.page.update()
        app.run(work)

    app.cleanups.append(stop.set)
    lv.controls = [ui.loading()]
    app.run(poll)
    composer = ft.Row([box, ft.IconButton(ft.Icons.SEND, on_click=lambda e: submit(), icon_color=ui.C.primary,
                                          tooltip="Send")])
    return ft.Column([older, lv, composer], expand=True, spacing=6)


# ---- feed --------------------------------------------------------------------------
def feed(app) -> ft.Control:
    state = {"tab": "fitness"}
    posts = ft.Column([ui.loading()], spacing=12)

    def load():
        try:
            items = app.api.call("get-posts", params={"tab": state["tab"]}).get("posts", [])
        except ApiError as ex:
            posts.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        posts.controls = [post_card(p) for p in items] or [ui.empty("No posts yet. Share the first one!", ft.Icons.FORUM_OUTLINED)]
        app.page.update()

    def post_card(p):
        user = p.get("users") or {}
        head = ft.Row([
            ft.Container(ui.avatar(user.get("username", "?"), 36), on_click=lambda e: open_profile(app, p["user_id"])),
            ft.Column([ft.Text(user.get("username", ""), color=ui.C.text, font_family="LatoBold"),
                       ui.body(f"{user.get('rank') or ''} · {ui.when(p.get('created_at'))}", size=11)],
                      spacing=0, expand=True),
        ])
        if p.get("user_id") == app.api.user_id:
            head.controls.append(ft.IconButton(ft.Icons.DELETE_OUTLINE, icon_color=ui.C.dim, tooltip="Delete post",
                                               on_click=lambda e: confirm_delete(p)))
        parts = [head]
        if p.get("title"):
            parts.append(ui.heading(p["title"], 16))
        parts.append(ft.Text(p.get("content", ""), color=ui.C.text, selectable=True))
        if p.get("image_url"):
            parts.append(ft.Image(src=p["image_url"], border_radius=10, fit=ft.BoxFit.COVER, height=260,
                                  width=float("inf")))
        if p.get("tab") == "food" and p.get("calories") is not None:
            parts.append(ui.body(f"{p['calories']} kcal · P {p.get('protein')} g · C {p.get('carbs')} g · F {p.get('fat')} g",
                                 color=ui.C.food, size=13))
            if p.get("ingredients"):
                parts.append(ui.body(f"Ingredients: {p['ingredients']}", size=13))
        return ui.card(ft.Column(parts, spacing=10))

    def confirm_delete(p):
        def go(e):
            app.page.pop_dialog()

            def work():
                try:
                    app.api.call("delete-post", "POST", {"post_id": p["id"]})
                    app.toast("Post deleted.")
                    load()
                except ApiError as ex:
                    app.toast(str(ex), error=True)
            app.run(work)
        app.page.show_dialog(ft.AlertDialog(title=ft.Text("Delete this post?"),
                                            content=ft.Text("The post and its photo are removed for good."),
                                            actions=[ui.button("Keep", lambda e: app.page.pop_dialog(), kind="text"),
                                                     ui.button("Delete", go, kind="danger")]))

    def switch(tab):
        state["tab"] = tab
        posts.controls = [ui.loading()]
        app.page.update()
        app.run(load)

    app.run(load)
    return ft.Column([
        ft.Row([ui.chips([("fitness", "Fitness"), ("food", "Food")], "fitness", switch),
                ui.button("New post", lambda e: new_post(app, state["tab"], lambda: app.run(load)), icon=ft.Icons.ADD)],
               alignment=ft.MainAxisAlignment.SPACE_BETWEEN, wrap=True),
        posts,
    ], spacing=12)


def new_post(app, tab: str, on_posted) -> None:
    state = {"tab": tab, "image": None}
    title = ui.field("Title (optional)", max_length=100)
    content = ui.field("What did you do today?", multiline=True, min_lines=3, max_lines=6, max_length=1000)
    ingredients = ui.field("Ingredients (optional)", multiline=True, max_lines=4, max_length=1000)
    macros = {k: ui.number_field(k.title() + (" (kcal)" if k == "calories" else " (g)"), decimals=True, expand=True)
              for k in ("calories", "protein", "carbs", "fat")}
    food_box = ft.Column([ingredients, ft.Row([macros["calories"], macros["protein"]]),
                          ft.Row([macros["carbs"], macros["fat"]])], spacing=10, visible=tab == "food")
    photo_note = ui.body("No photo", size=12)

    def set_tab(t):
        state["tab"] = t
        food_box.visible = t == "food"
        app.page.update()

    async def pick_photo(e):
        files = await app.picker.pick_files(dialog_title="Choose a photo", file_type=ft.FilePickerFileType.IMAGE,
                                            with_data=True)
        if not files:
            return
        f = files[0]
        jpg = prepare_jpeg(f.bytes or b"", f.name)
        if jpg is None:
            app.toast("Use a JPEG photo under 2 MB.", error=True)
            return
        state["image"] = jpg
        photo_note.value = f"{f.name} · {len(jpg) // 1024} KB"
        photo_note.update()

    def submit(e):
        body = {"tab": state["tab"], "content": content.value.strip(), "title": title.value.strip() or None}
        if not body["content"]:
            app.toast("Write something first.", error=True)
            return
        if state["tab"] == "food":
            if not all(m.value for m in macros.values()):
                app.toast("Food posts need calories, protein, carbs and fat.", error=True)
                return
            body.update({k: float(m.value) for k, m in macros.items()}, ingredients=ingredients.value.strip() or None)
        if state["image"]:
            body["image_base64"] = base64.b64encode(state["image"]).decode()
        app.page.pop_dialog()

        def work():
            try:
                res = app.api.call("create-post", "POST", body)
            except ApiError as ex:
                app.toast(str(ex), error=True)
                return
            gold = res.get("gold_awarded")
            app.toast("Posted!" + (f" +{gold} gold" if gold else ""))
            on_posted()
        app.run(work)

    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text("New post"), scrollable=True,
        content=ft.Column([ui.chips([("fitness", "Fitness"), ("food", "Food")], tab, set_tab), title, content, food_box,
                           ft.Row([ui.button("Add photo", pick_photo, icon=ft.Icons.PHOTO_OUTLINED, kind="ghost"),
                                   photo_note], wrap=True)],
                          tight=True, spacing=12, width=480),
        actions=[ui.button("Cancel", lambda e: app.page.pop_dialog(), kind="text"), ui.button("Post", submit)]))


# ---- chat ---------------------------------------------------------------------------
def chat(app) -> ft.Control:
    def fetch(before):
        params = {"limit": 30, **({"before": before} if before else {})}
        res = app.api.call("chat-history", params=params)
        return res.get("messages", []), res.get("has_more", False)

    def bubble(m):
        mine = m.get("user_id") == app.api.user_id
        return ft.Container(ft.Column([
            ft.Row([ft.Text(m.get("username", ""), color=ui.C.accent if not mine else ui.C.primary_bright,
                            font_family="LatoBold", size=13),
                    ui.body(ui.when(m.get("created_at")), size=11)], spacing=8),
            ft.Text(m.get("message", ""), color=ui.C.text, selectable=True),
        ], spacing=2), padding=ft.Padding.symmetric(horizontal=12, vertical=8), border_radius=12,
            bgcolor=ui.fade(ui.C.primary, 0x22) if mine else ui.C.panel, on_click=None if mine else lambda e: message_menu(m))

    def message_menu(m):
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text(m.get("username", "")),
            content=ft.Text(m.get("message", ""), color=ui.C.dim),
            actions=[ui.button("View profile", lambda e: (app.page.pop_dialog(), open_profile(app, m["user_id"])), kind="text"),
                     ui.button("Report", lambda e: (app.page.pop_dialog(),
                                                    report_dialog(app, m["user_id"], m.get("username", ""), m, "chat")),
                               kind="text")]))

    panel = chat_panel(app, fetch, lambda t: app.api.call("chat-send", "POST", {"message": t}), bubble, 5,
                       "Message the Gymunnity...")
    return ft.Container(panel, height=max(360, (app.page.height or 800) - 250))


# ---- friends + DMs -------------------------------------------------------------------
def friends(app) -> ft.Control:
    lists = ft.Column([ui.loading()], spacing=10)
    results = ft.Column(spacing=8)
    search = ui.field("Find people by username", prefix_icon=ft.Icons.PERSON_SEARCH, expand=True)

    def act(fn: str, body: dict, ok: str):
        def work():
            try:
                app.api.call(fn, "POST", body)
                app.toast(ok)
            except ApiError as ex:
                app.toast(str(ex), error=True)
            load()
            if search.value.strip():
                do_search_work(search.value.strip())
        app.run(work)

    def person(u: dict, trailing: list[ft.Control]) -> ft.Control:
        return ui.card(ft.Row([
            ft.Container(ui.avatar(u.get("username", "?"), 36), on_click=lambda e: open_profile(app, u["id"])),
            ft.Column([ft.Text(u.get("username", ""), color=ui.C.text, font_family="LatoBold"),
                       ui.body(f"{u.get('rank') or 'Unranked'} · {ui.FOCUS_LABEL.get(u.get('focus_type'), '')}", size=12)],
                      spacing=0, expand=True),
            *trailing]), padding=10)

    def load():
        try:
            res = app.api.call("get-friends")
        except ApiError as ex:
            lists.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        rows: list[ft.Control] = []
        if res.get("incomingRequests"):
            rows.append(ui.label("Requests", ui.C.accent))
            rows += [person(r["user"], [
                ui.button("Accept", lambda e, r=r: act("respond-friend-request", {"request_id": r["friendship_id"], "action": "accept"}, "Friend added."), kind="accent"),
                ft.IconButton(ft.Icons.CLOSE, tooltip="Decline", on_click=lambda e, r=r: act(
                    "respond-friend-request", {"request_id": r["friendship_id"], "action": "decline"}, "Request declined.")),
            ]) for r in res["incomingRequests"]]
        rows.append(ui.label(f"Friends ({len(res.get('friends', []))})"))
        rows += [person(f["user"], [
            ft.IconButton(ft.Icons.CHAT_OUTLINED, tooltip="Message", icon_color=ui.C.primary,
                          on_click=lambda e, f=f: app.open(dm, f["user"])),
            ft.IconButton(ft.Icons.PERSON_REMOVE_OUTLINED, tooltip="Remove friend", icon_color=ui.C.dim,
                          on_click=lambda e, f=f: confirm_remove(f["user"])),
        ]) for f in res.get("friends", [])] or [ui.empty("No friends yet. Search for people above.", ft.Icons.GROUP_ADD)]
        if res.get("outgoingRequests"):
            rows.append(ui.label("Sent requests"))
            rows += [person(r["user"], [ui.body("Pending", size=12)]) for r in res["outgoingRequests"]]
        lists.controls = rows
        app.page.update()

    def confirm_remove(u):
        def go(e):
            app.page.pop_dialog()
            act("remove-friend", {"friend_id": u["id"]}, f"Removed {u['username']}.")
        app.page.show_dialog(ft.AlertDialog(title=ft.Text(f"Remove {u['username']}?"),
                                            content=ft.Text("You won't be able to message each other until you're friends again."),
                                            actions=[ui.button("Cancel", lambda e: app.page.pop_dialog(), kind="text"),
                                                     ui.button("Remove", go, kind="danger")]))

    def do_search_work(q):
        try:
            found = app.api.call("search-users", params={"query": q}).get("results", [])
        except ApiError as ex:
            results.controls = [ui.error_box(str(ex))]
            app.page.update()
            return
        results.controls = [person(u, [status_button(u)]) for u in found] or [ui.empty(f"Nobody called “{q}”.", ft.Icons.SEARCH_OFF)]
        app.page.update()

    def status_button(u):
        s = u.get("friendship_status")
        if s == "accepted":
            return ft.IconButton(ft.Icons.CHAT_OUTLINED, tooltip="Message", on_click=lambda e: app.open(dm, u))
        if s == "pending_outgoing":
            return ui.body("Requested", size=12)
        if s == "pending_incoming":
            return ui.body("Wants to be friends", size=12, color=ui.C.accent)
        return ui.button("Add", lambda e: act("send-friend-request", {"addressee_id": u["id"]}, "Request sent."),
                         icon=ft.Icons.PERSON_ADD, kind="ghost")

    def do_search(e=None):
        q = search.value.strip()
        if len(q) >= 2:
            results.controls = [ui.loading("Searching...")]
            app.page.update()
            app.run(do_search_work, q)

    search.on_submit = do_search
    app.run(load)
    return ft.Column([ft.Row([search, ft.IconButton(ft.Icons.SEARCH, on_click=do_search)]), results, lists], spacing=12)


def dm(app, friend: dict) -> ft.Control:
    def fetch(before):
        params = {"friend_id": friend["id"], "limit": 30, **({"before": before} if before else {})}
        res = app.api.call("get-dm-history", params=params)
        return res.get("messages", []), res.get("has_more", False)

    def bubble(m):
        mine = m.get("sender_id") == app.api.user_id
        return ft.Row([ft.Container(
            ft.Column([ft.Text(m.get("message", ""), color=ui.C.text, selectable=True),
                       ui.body(ui.when(m.get("created_at")), size=10)], spacing=2,
                      horizontal_alignment=ft.CrossAxisAlignment.END if mine else ft.CrossAxisAlignment.START),
            padding=ft.Padding.symmetric(horizontal=12, vertical=8), border_radius=14,
            bgcolor=ui.fade(ui.C.primary, 0x44) if mine else ui.C.panel_alt,
            on_click=None if mine else lambda e: report_dialog(app, friend["id"], friend["username"], m, "dm"),
            tooltip=None if mine else "Tap to report")],
            alignment=ft.MainAxisAlignment.END if mine else ft.MainAxisAlignment.START)

    panel = chat_panel(app, fetch, lambda t: app.api.call("send-dm", "POST", {"recipient_id": friend["id"], "message": t}),
                       bubble, 4, f"Message {friend['username']}...")
    head = ft.Row([ui.avatar(friend["username"], 36), ui.heading(friend["username"], 16)])
    return ui.screen("Messages", ft.Container(head, on_click=lambda e: open_profile(app, friend["id"])),
                     ft.Container(panel, height=max(360, (app.page.height or 800) - 220)))


# ---- leaderboard ----------------------------------------------------------------------
def leaderboard(app) -> ft.Control:
    rows = ft.Column([ui.loading()], spacing=8)
    mine = app.me["profile"].get("focus_type") or "hybrid"

    def load(path):
        try:
            board = app.api.call("leaderboard", params={"focus_type": path})
        except ApiError as ex:
            rows.controls = [ui.error_box(str(ex))]
            app.page.update()
            return
        medal = {0: ui.C.gold, 1: "#cbd5e1", 2: "#d97706"}
        me_name = app.me["profile"].get("username")
        rows.controls = [ui.card(ft.Row([
            ft.Container(ui.num(i + 1, 18, medal.get(i, ui.C.dim)), width=36),
            ui.avatar(r.get("username", "?"), 34, medal.get(i, ui.C.primary)),
            ft.Column([ft.Text(r.get("username", ""), color=ui.C.text, font_family="LatoBold"),
                       ui.body(ui.rank_text(r), size=12)], spacing=0, expand=True),
            ft.Text(f"{int(r.get('xp') or 0):,} XP", color=ui.C.primary_bright, font_family="LatoBold"),
        ]), padding=10, accent=ui.C.accent if r.get("username") == me_name else None)
            for i, r in enumerate(board or [])] or [ui.empty("No one on this path yet.", ft.Icons.LEADERBOARD)]
        app.page.update()

    def pick(e):
        rows.controls = [ui.loading()]
        app.page.update()
        app.run(load, e.control.value)

    app.run(load, mine)
    return ui.screen("Leaderboard", ui.dropdown("Path", ui.FOCUS_TYPES, mine, on_select=pick), rows,
                     subtitle="Top 50 by XP on each training path.")


# ---- tab ----------------------------------------------------------------------------
SECTIONS = [("feed", "Feed"), ("chat", "Chat"), ("friends", "Friends")]
BUILDERS = {"feed": feed, "chat": chat, "friends": friends}
_start = {"tab": "feed"}


def open_tab(app, section: str) -> None:
    _start["tab"] = section
    app.go("social")


def view(app) -> ft.Control:
    first, _start["tab"] = _start["tab"], "feed"
    holder = ft.Container(BUILDERS[first](app))

    def switch(key):
        app.leave()  # stop the chat poller when switching away from it
        holder.content = BUILDERS[key](app)
        app.page.update()

    return ui.screen("Gymunnity", ui.chips(SECTIONS, first, switch), holder,
                     actions=[ft.IconButton(ft.Icons.LEADERBOARD, tooltip="Leaderboard",
                                            on_click=lambda e: app.open(leaderboard))])
