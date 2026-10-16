"""The game layer: Missions (boss fights you clear with sets), the gold Shop, your Collection,
and the Dungeon board. Damage, rewards and unlocks are all decided by the server."""
import uuid

import flet as ft

import ui
from api import ApiError
from views.home import NAMES

GRADE_COLOR = {"S": ui.C.gold, "A": ui.C.food, "B": ui.C.primary_bright, "C": ui.C.dim}


def target_text(o: dict) -> str:
    name = NAMES.get(o.get("exercise"), o.get("exercise", ""))
    unit = " s" if o.get("metric_type") == "duration" else " reps"
    return f"{name} · {int(o.get('target_value') or 0)}{unit}"


# ---- missions ---------------------------------------------------------------------------
def missions(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=12)

    def load():
        try:
            board = app.api.call("missions")
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        active = board.get("active_attempt")
        every = {m["id"]: m for ch in board.get("chapters", []) for m in ch.get("missions", [])}
        rows: list[ft.Control] = []
        if active and active.get("mission_id") in every:  # resume it: starting again would abandon it
            rows.append(ui.card(ft.Row([
                ft.Icon(ft.Icons.BOLT, color=ui.C.gold),
                ft.Column([ui.heading(f"In progress: {active['mission_name']}", 15),
                           ui.body(f"Boss HP {active['boss_hp']}/{active['max_hp']}", size=12)], spacing=2, expand=True),
                ui.button("Continue", lambda e: app.open(fight, every[active["mission_id"]], active)),
            ]), accent=ui.C.gold))
        for ch in board.get("chapters", []):
            rows.append(ui.section(f"Chapter {ch['number']} · {ch['name']}"))
            for m in ch.get("missions", []):
                rows.append(mission_card(m, ch))
        rows.append(ui.body(f"{board.get('cleared_count', 0)} missions cleared. Clearing a level unlocks the next.",
                            size=12))
        box.controls = rows or [ui.empty("No missions yet.", ft.Icons.FLAG)]
        app.page.update()

    def mission_card(m, ch):
        locked = not m.get("unlocked")
        right = (ui.tag(f"grade {m['grade']}", GRADE_COLOR.get(m.get("grade"), ui.C.dim)) if m.get("cleared")
                 else ft.Icon(ft.Icons.LOCK_OUTLINE, color=ui.C.faint) if locked
                 else ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim))
        return ui.card(ft.Row([
            ft.Container(ui.num(m["level_number"], 18, ui.C.faint if locked else ui.C.accent), width=34),
            ft.Column([ft.Text(m["name"] + (" · BOSS" if m.get("is_boss_level") else ""),
                               color=ui.C.faint if locked else ui.C.text, font_family="LatoBold"),
                       ui.body(f"{m.get('difficulty', '').title()} · {m.get('objective_count', 0)} sets · "
                               f"+{m.get('reward_xp', 0)} XP · +{m.get('reward_gold', 0)} gold", size=12)],
                      spacing=2, expand=True),
            right,
        ]), padding=12, on_click=None if locked else (lambda e, m=m: app.open(fight, m)))

    app.run(load)
    return box


def fight(app, mission: dict, attempt: dict | None = None) -> ft.Control:
    """A mission run: the current objective, the boss's HP, and a manual set result.
    Begin set starts the server's timer, so a too-fast result is refused as implausible."""
    mission_id = mission["id"]
    st = {"attempt": attempt, "objectives": mission.get("objectives") or [], "started": False}
    body = ft.Column([ui.loading()], spacing=12)
    achieved = ui.number_field("Reps (or seconds) you did", "", expand=True)

    def call(payload, then):
        def work():
            try:
                res = app.api.call("mission-attempt", "POST", payload)
            except ApiError as ex:
                app.toast(str(ex), error=True)
                return render()
            then(res)
        app.run(work)

    def start(e=None):
        call({"action": "start", "mission_id": mission_id}, lambda r: (
            st.update(attempt=r, objectives=r.get("objectives") or st["objectives"], started=False), render()))

    def begin(e):
        a = st["attempt"]
        def started(r):
            if r.get("success") is False:  # e.g. the timer ran out on the server
                st["attempt"] = None
                app.toast(r.get("message") or "This attempt has ended.", error=True)
            else:
                st["started"] = True
            render()
        call({"action": "objective_start", "attempt_id": a["attempt_id"]}, started)

    def submit(e):
        a = st["attempt"]
        if not achieved.value:
            app.toast("Enter what you did.", error=True)
            return
        payload = {"action": "submit", "attempt_id": a["attempt_id"], "achieved": int(achieved.value),
                   "workout_source": "manual"}

        def done(r):
            achieved.value = ""
            st["started"] = False
            a.update(boss_hp=r.get("boss_hp", a.get("boss_hp")), current_sequence=r.get("current_sequence", a.get("current_sequence")))
            if r.get("mission_complete") or r.get("status") in ("failed", "cleared", "completed"):
                st["attempt"] = None
            app.toast(r.get("message") or ("Mission cleared!" if r.get("mission_complete") else "Set recorded."))
            render(r if r.get("mission_complete") else None)
        call(payload, done)

    def abandon(e):
        call({"action": "abandon", "attempt_id": st["attempt"]["attempt_id"]},
             lambda r: (st.update(attempt=None), app.toast("Mission abandoned."), render()))

    def pause(e):
        def work():
            try:
                app.api.call("shop", "POST", {"action": "use", "item_key": "pause_potion", "context_type": "mission_attempt",
                                              "context_id": st["attempt"]["attempt_id"]})
                app.toast("Paused for 2 minutes.")
            except ApiError as ex:
                app.toast(str(ex), error=True)
        app.run(work)

    def render(result: dict | None = None):
        a, objs = st["attempt"], st["objectives"]
        rows: list[ft.Control] = []
        if result:
            won = result.get("rewards") or {}
            rows.append(ui.card(ft.Column([
                ui.heading("Mission cleared!", 18, ui.C.gold),
                ui.body(f"Grade {result.get('grade', '?')} · +{won.get('xp') or 0} XP · +{won.get('gold') or 0} gold"
                        + (" · new collectible!" if won.get("collectible") else "")
                        + ("" if result.get("first_clear") else " (rewards are for the first clear)"), color=ui.C.text),
            ], spacing=6), accent=ui.C.gold))
        if mission.get("boss_name"):
            rows.append(ui.card(ft.Column([ui.heading(mission["boss_name"], 16, ui.C.danger),
                                           ui.body(mission.get("boss_lore") or "", size=13)], spacing=4)))
        if a:
            rows.append(ui.label(f"Boss HP {a['boss_hp']} / {a['max_hp']}", ui.C.danger))
            rows.append(ui.xp_bar(a["boss_hp"] / max(a["max_hp"], 1), ui.C.danger, end_color=ui.C.gold))
            current = next((o for o in objs if o.get("sequence") == a.get("current_sequence")), None)
            if current:
                rows.append(ui.card(ft.Column([
                    ui.label(f"Set {current['sequence']} of {len(objs)}"),
                    ui.heading(target_text(current), 18),
                    ui.body("Tap Begin set, do it, then enter what you did. Results faster than humanly "
                            "possible are refused.", size=12),
                    ui.button("Begin set", begin, icon=ft.Icons.PLAY_ARROW, kind="camera") if not st["started"]
                    else ft.Row([achieved, ui.button("Submit", submit, icon=ft.Icons.CHECK)], spacing=10),
                ], spacing=10)))
            rows.append(ft.Row([ui.button("Use pause potion", pause, icon=ft.Icons.PAUSE, kind="ghost"),
                                ui.button("Abandon", abandon, kind="text")], wrap=True))
        else:
            rows += [ui.card(ft.Column([ui.body(target_text(o), color=ui.C.text) for o in objs] or
                                       [ui.body("Objectives appear when you start.")], spacing=6), width=float("inf")),
                     ui.button("Start mission" if not result else "Play again", start, icon=ft.Icons.FLAG,
                               width=float("inf"))]
        body.controls = rows
        app.page.update()

    render()
    return ui.screen(mission.get("name", "Mission"), body,
                     subtitle="Clear every set before the timer runs out.")


# ---- shop + collection ------------------------------------------------------------------
def shop(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)

    def load():
        try:
            res = app.api.call("shop")
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        rows: list[ft.Control] = [ui.stat("Gold", int(res.get("balance") or 0), ui.C.gold, ft.Icons.PAID_OUTLINED,
                                          width=float("inf"))]
        if res.get("restorable_date"):
            rows.append(ui.body(f"A Streak Restore can cover {res['restorable_date']}.", color=ui.C.gold, size=13))
        for it in res.get("items", []):
            usable = it.get("scope") == "global" and it.get("owned")
            rows.append(ui.card(ft.Column([
                ft.Row([ft.Text(it["name"], color=ui.C.text, font_family="LatoBold", expand=True),
                        ui.tag(f"{it['price_gold']} gold", ui.C.gold)]),
                ui.body(it.get("description", ""), size=13),
                ft.Row([ui.body(f"Owned {it.get('owned', 0)}/{it.get('max_stack')}", size=12),
                        ft.Container(expand=True),
                        *([ui.button("Use", lambda e, it=it: act({"action": "use", "item_key": it["key"],
                                                                  "context_type": "streak"}), kind="ghost")] if usable else []),
                        ui.button("Buy", lambda e, it=it: act({"action": "purchase", "item_key": it["key"], "quantity": 1,
                                                               "request_id": str(uuid.uuid4())}), kind="accent")]),
            ], spacing=6), padding=12))
        box.controls = rows
        app.page.update()

    def act(payload):
        def work():
            try:
                r = app.api.call("shop", "POST", payload)
                app.toast(r.get("message") or ("Bought." if payload["action"] == "purchase" else "Used."))
            except ApiError as ex:
                app.toast(str(ex), error=True)
            load()
        app.run(work)

    app.run(load)
    return ui.screen("Shop", box, subtitle="Spend the gold you earn from meals, posts, missions and dungeons.")


def collection(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)

    def load():
        try:
            res = app.api.call("collection")
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        owned = res.get("owned", [])
        box.controls = [ui.body(f"{len(owned)} of {res.get('total_collectibles', 0)} collected.", size=13)] + [
            ui.card(ft.Row([
                ft.Icon(ft.Icons.DIAMOND, color=c.get("color") or ui.C.accent),
                ft.Column([ft.Text(c["name"], color=ui.C.text, font_family="LatoBold"),
                           ui.body(f"{(c.get('rarity') or '').title()} {c.get('kind', '')} · {c.get('description') or ''}", size=12)],
                          spacing=2, expand=True),
                ft.Switch(value=bool(c.get("equipped")), tooltip="Wear it",
                          on_change=lambda e, c=c: equip(c, e.control.value)),
            ]), padding=12) for c in owned] or [
            ui.empty("Nothing yet. Clear missions and dungeons to earn collectibles.", ft.Icons.DIAMOND_OUTLINED)]
        app.page.update()

    def equip(c, on):
        def work():
            try:
                app.api.call("collection", "POST", {"collectible_id": c["collectible_id"], "equipped": on})
            except ApiError as ex:
                app.toast(str(ex), error=True)
            load()
        app.run(work)

    app.run(load)
    return ui.screen("Collection", box)


# ---- dungeons ---------------------------------------------------------------------------
def dungeons(app) -> ft.Control:
    """Open Dungeon events and the Dungeon leaderboard. Fighting one is a live party battle on the
    camera, which this app doesn't run, so this is the board, not the fight."""
    events = ft.Column([ui.loading()], spacing=10)
    board = ft.Column([ui.loading()], spacing=8)

    def load():
        try:
            res = app.api.call("dungeons")
            top = app.api.call("dungeon-leaderboard", params={"scope": "clears"})
        except ApiError as ex:
            events.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            board.controls = []
            app.page.update()
            return
        events.controls = [ui.card(ft.Column([
            ft.Row([ui.tag(e.get("rank_label") or e.get("threat_rank") or "?", ui.C.danger),
                    ft.Text(e["name"], color=ui.C.text, font_family="LatoBold", expand=True),
                    *([ui.tag("cleared", ui.C.food)] if e.get("cleared") else [])]),
            ui.body(f"Boss: {e.get('boss_name')} · HP {e.get('boss_max_hp')} · ends {ui.when(e.get('ends_at'))}", size=12),
            ui.body(e.get("boss_lore") or "", size=12),
        ], spacing=6), padding=12) for e in res.get("events", [])] or [
            ui.empty("No Dungeon is open right now. Admins open them as events.", ft.Icons.CASTLE)]
        board.controls = [ui.card(ft.Row([
            ft.Container(ui.num(r["position"], 16, ui.C.gold if r["position"] == 1 else ui.C.dim), width=34),
            ft.Text(r.get("username", ""), color=ui.C.text, expand=True),
            ui.body(f"{r.get('clears', 0)} clears · {int(r.get('damage') or 0):,} dmg", size=12),
        ]), padding=10) for r in top.get("entries", [])] or [ui.empty("No clears yet.", ft.Icons.LEADERBOARD)]
        app.page.update()

    app.run(load)
    return ui.screen("Dungeons", ui.section("Open now"), events, ui.section("Top gate closers"), board,
                     subtitle="Party boss fights. Join and fight on the AWXCEND web app; standings show here.")
