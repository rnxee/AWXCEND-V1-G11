"""Routines: saved lists of exercises with target sets/reps (or seconds). Make, edit, delete,
then do one: each exercise opens a log prefilled with its targets."""
import flet as ft

import ui
from api import ApiError
from views.home import NAMES
from views.train import EXERCISES, TIMED, log_workout


def payload(name: str, notes: str, rows: list[tuple[str, str, str]]) -> dict | str:
    """save-routine body from the editor's rows (exercise, sets, reps-or-seconds), or what's wrong."""
    if not name.strip():
        return "Give the routine a name."
    exercises = []
    for i, (ex, sets, amount) in enumerate(rows, 1):
        if ex not in NAMES:
            return f"Pick an exercise from the list in row {i}."
        s, a = int(sets or 0), int(amount or 0)
        if not 1 <= s <= 20:
            return f"Row {i}: sets must be 1-20."
        if ex in TIMED and not 1 <= a <= 21600:
            return f"Row {i}: seconds must be 1-21600."
        if ex not in TIMED and not 1 <= a <= 300:
            return f"Row {i}: reps must be 1-300."
        exercises.append({"exercise": ex, "target_sets": s,
                          **({"target_duration_seconds": a} if ex in TIMED else {"target_reps": a})})
    if not exercises:
        return "Add at least one exercise."
    return {"name": name.strip()[:80], "notes": notes.strip()[:500] or None, "exercises": exercises}


def target_text(e: dict) -> str:
    sets = e.get("target_sets") or 1
    if e.get("target_duration_seconds"):
        s = e["target_duration_seconds"]
        return f"{sets} × {s // 60}:{s % 60:02d}"
    return f"{sets} × {e.get('target_reps') or '?'}"


def editor(app, routine: dict | None, on_saved) -> None:
    name = ui.field("Routine name", value=(routine or {}).get("name", ""), max_length=80)
    notes = ui.field("Notes (optional)", value=(routine or {}).get("notes") or "", multiline=True, max_lines=3,
                     max_length=500)
    rows: list[dict] = []
    box = ft.Column(spacing=10)
    error = ft.Text("", color=ui.C.danger, visible=False)

    def add_row(ex="squat", sets=3, amount=10):
        pick = ui.dropdown("Exercise", EXERCISES, ex, enable_filter=True, editable=True)
        s = ui.number_field("Sets", sets, expand=True)
        a = ui.number_field("Seconds" if ex in TIMED else "Reps", amount, expand=True)

        def on_pick(e):
            a.label = "Seconds" if pick.value in TIMED else "Reps"
            a.update()
        pick.on_select = on_pick
        row = {"pick": pick, "sets": s, "amount": a}
        remove = ft.IconButton(ft.Icons.REMOVE_CIRCLE_OUTLINE, icon_color=ui.C.danger, tooltip="Remove",
                               on_click=lambda e: (rows.remove(row), render()))
        row["control"] = ui.card(ft.Column([pick, ft.Row([s, a, remove], spacing=8)], spacing=8), padding=10)
        rows.append(row)

    def render():
        box.controls = [r["control"] for r in rows] or [ui.body("No exercises yet.", size=12)]
        app.page.update()

    for e in (routine or {}).get("routine_exercises") or []:
        timed = e.get("target_duration_seconds")
        add_row(e["exercise"], e.get("target_sets") or 3, timed or e.get("target_reps") or 10)
    if not rows:
        add_row()
    box.controls = [r["control"] for r in rows]

    def save(e):
        body = payload(name.value, notes.value,
                       [(r["pick"].value, r["sets"].value, r["amount"].value) for r in rows])
        if isinstance(body, str):
            error.value, error.visible = body, True
            app.page.update()
            return
        if routine:
            body["routine_id"] = routine["id"]
        app.close_dialog()

        def work():
            try:
                app.api.call("save-routine", "POST", body)
                app.toast("Routine saved.")
            except ApiError as ex:
                app.toast(str(ex), error=True)
            on_saved()
        app.run(work)

    app.page.show_dialog(ft.AlertDialog(
        title=ft.Text("Edit routine" if routine else "New routine"), scrollable=True,
        content=ft.Column([name, notes, ui.section("Exercises"), box,
                           ui.button("Add exercise", lambda e: (add_row(), render()), icon=ft.Icons.ADD, kind="ghost"),
                           error], tight=True, spacing=12, width=480),
        actions=[ui.button("Cancel", lambda e: app.close_dialog(), kind="text"), ui.button("Save", save)]))


def run(app, routine: dict) -> ft.Control:
    """Do a routine: tap an exercise to log it with its targets filled in."""
    done: set[int] = set()
    rows = ft.Column(spacing=10)

    def log_dialog(i: int, e: dict):
        ex = e["exercise"]
        timed = ex in TIMED
        sets = ui.number_field("Sets", e.get("target_sets") or 1, expand=True)
        amount = ui.number_field("Seconds" if timed else "Reps",
                                 e.get("target_duration_seconds") if timed else e.get("target_reps") or 10, expand=True)
        weight = ui.number_field("Weight (kg, optional)", "", decimals=True, expand=True)

        def save(ev):
            s, a = int(sets.value or 0), int(amount.value or 0)
            if timed:  # a timed set is logged as its total time: 3 × 1:00 plank = 3:00
                if not (1 <= s <= 20 and 1 <= s * a <= 21600):
                    app.toast("Sets must be 1-20 and the total time at most 6 hours.", error=True)
                    return
                data = {"exercise": ex, "duration_seconds": s * a}
            else:
                if not (1 <= s <= 20 and 1 <= a <= 300):
                    app.toast("Sets must be 1-20 and reps 1-300.", error=True)
                    return
                data = {"exercise": ex, "sets": s, "reps": a, "weight_kg": float(weight.value) if weight.value else None}
            app.close_dialog()

            def logged(ok):
                if ok:
                    done.add(i)
                    render()
            log_workout(app, data, logged)

        fields = [ft.Row([sets, amount], spacing=10)] + ([] if timed else [weight])
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text(NAMES.get(ex, ex)),
            content=ft.Column(fields, tight=True, spacing=12, width=400),
            actions=[ui.button("Cancel", lambda ev: app.close_dialog(), kind="text"),
                     ui.button("Log", save, icon=ft.Icons.CHECK)]))

    def render():
        items = routine.get("routine_exercises") or []
        rows.controls = [ui.card(ft.Row([
            ft.Icon(ft.Icons.CHECK_CIRCLE if i in done else ft.Icons.RADIO_BUTTON_UNCHECKED,
                    color=ui.C.food if i in done else ui.C.dim),
            ft.Column([ft.Text(NAMES.get(e["exercise"], e["exercise"]), color=ui.C.text, font_family="LatoBold"),
                       ui.body(target_text(e) + (f" · {e['notes']}" if e.get("notes") else ""), size=12)],
                      spacing=2, expand=True),
            ft.Icon(ft.Icons.CHEVRON_RIGHT, color=ui.C.dim),
        ]), padding=12, on_click=lambda ev, i=i, e=e: log_dialog(i, e)) for i, e in enumerate(items)]
        app.page.update()

    render()
    return ui.screen(routine["name"], *([ui.body(routine["notes"])] if routine.get("notes") else []), rows,
                     subtitle=f"Tap an exercise to log it. {len(routine.get('routine_exercises') or [])} exercises.")


def view(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)

    def render(items, *, offline=False, cached_at=None):
        notice = []
        if offline:
            stamp = f" Last updated {ui.when(cached_at)}." if cached_at else ""
            notice = [ui.card(ft.Row([ft.Icon(ft.Icons.WIFI_OFF, color=ui.C.gold),
                                       ui.body(f"Offline mode · showing your saved routines.{stamp}", size=12)]),
                              accent=ui.fade(ui.C.gold, 0x88))]
        box.controls = notice + [card(r) for r in items] or [
            ui.empty("No saved routines on this device. Connect once to load or create one.", ft.Icons.LIST_ALT)]
        app.page.update()

    def load():
        try:
            items = app.api.call("get-routines").get("routines", [])
        except ApiError as ex:
            cached, stamp = app.store.cached_routines()
            if cached:
                render(cached, offline=True, cached_at=stamp)
            else:
                box.controls = [ui.empty("No routines are cached yet. Connect to the internet once to load them.",
                                         ft.Icons.WIFI_OFF), ui.error_box(str(ex), lambda: app.run(load))]
                app.page.update()
            return
        app.store.cache_routines(items)
        render(items)

    def card(r):
        exs = r.get("routine_exercises") or []
        summary = ", ".join(NAMES.get(e["exercise"], e["exercise"]) for e in exs[:4]) + ("…" if len(exs) > 4 else "")
        return ui.card(ft.Column([
            ft.Row([ft.Column([ui.heading(r["name"], 16), ui.body(f"{len(exs)} exercises · {summary}", size=12)],
                              spacing=2, expand=True),
                    ft.IconButton(ft.Icons.EDIT_OUTLINED, tooltip="Edit", icon_color=ui.C.primary_bright,
                                  on_click=lambda e: editor(app, r, lambda: app.run(load))),
                    ft.IconButton(ft.Icons.DELETE_OUTLINE, tooltip="Delete", icon_color=ui.C.dim,
                                  on_click=lambda e: confirm_delete(r))]),
            ui.button("Start", lambda e: app.open(run, r), icon=ft.Icons.PLAY_ARROW, width=float("inf")),
        ], spacing=10), padding=14)

    def confirm_delete(r):
        def go(e):
            app.close_dialog()

            def work():
                try:
                    app.api.call("delete-routine", "POST", {"routine_id": r["id"]})
                    app.toast("Routine deleted.")
                except ApiError as ex:
                    app.toast(str(ex), error=True)
                load()
            app.run(work)
        app.page.show_dialog(ft.AlertDialog(
            title=ft.Text(f"Delete “{r['name']}”?"), content=ft.Text("Workouts you already logged stay."),
            actions=[ui.button("Keep", lambda e: app.close_dialog(), kind="text"),
                     ui.button("Delete", go, kind="danger")]))

    app.run(load)
    return ui.screen("Routines", box, subtitle="Your saved workouts.",
                     actions=[ui.button("New", lambda e: editor(app, None, lambda: app.run(load)), icon=ft.Icons.ADD)])
