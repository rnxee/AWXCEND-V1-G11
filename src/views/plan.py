"""Training plan (a short survey, then a month of sessions) and the food budget helper.
The server makes the plan and works out every price; the app shows them and records your choices."""
from datetime import date

import flet as ft

import ui
from api import ApiError

GOALS = [("muscle", "Build muscle"), ("fat_loss", "Lose fat"), ("strength", "Get stronger"),
         ("endurance", "Endurance"), ("general", "General fitness")]
EXPERIENCE = [("new", "New"), ("some", "Some"), ("experienced", "Experienced")]
MINUTES = [("20", "20 min"), ("30", "30 min"), ("45", "45 min"), ("60", "60 min")]
EQUIPMENT = [("bodyweight", "Bodyweight"), ("dumbbells", "Dumbbells"), ("gym", "Full gym")]
WEEKDAYS = [("mon", "Mon"), ("tue", "Tue"), ("wed", "Wed"), ("thu", "Thu"), ("fri", "Fri"), ("sat", "Sat"), ("sun", "Sun")]


def survey_answers(goal, experience, days: list[str], minutes, equipment) -> dict | str:
    """training-plan's survey body, or what's missing (the server checks it again)."""
    if not 2 <= len(days) <= 6:
        return "Pick 2 to 6 training days a week - rest days matter too."
    return {"goal": goal, "experience": experience, "days": [d for d, _ in WEEKDAYS if d in days],
            "minutes": int(minutes), "equipment": equipment, "preferCamera": False}


def dose(x: dict) -> str:
    amount = f"{x['seconds']} s" if x.get("seconds") else f"{x.get('reps') or '?'} reps"
    return f"{x.get('label') or x.get('exercise')} · {x.get('sets', 1)} × {amount}"


def training(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=12)

    def call(payload=None):
        def work():
            try:
                res = app.api.call("training-plan", "POST" if payload else "GET", payload)
            except ApiError as ex:
                cached, stamp = app.store.cached_plan()
                if cached and cached.get("plan"):
                    show(cached, offline=True, cached_at=stamp)
                else:
                    box.controls = [ui.empty("No training plan is cached yet. Connect to the internet once to load it.",
                                             ft.Icons.WIFI_OFF), ui.error_box(str(ex), lambda: app.run(load))]
                    app.page.update()
                return
            if res.get("plan"):
                app.store.cache_plan(res)
            show(res)  # GET, submit_survey and next_month all answer with the whole plan state
        app.run(work)

    def load():
        call()

    def show(res, *, offline=False, cached_at=None):
        plan = res.get("plan")
        box.controls = days_view(res, plan, offline=offline, cached_at=cached_at) if plan else [survey(res)]
        app.page.update()

    def survey(res):
        st = {"goal": "general", "experience": "some", "minutes": "45", "equipment": "gym"}
        days = {"mon", "wed", "fri"}
        error = ft.Text("", color=ui.C.danger, visible=False)

        def go(e):
            answers = survey_answers(st["goal"], st["experience"], list(days), st["minutes"], st["equipment"])
            if isinstance(answers, str):
                error.value, error.visible = answers, True
                app.page.update()
                return
            box.controls = [ui.loading("Making your plan...")]
            app.page.update()
            call({"action": "submit_survey", "answers": answers})

        return ui.card(ft.Column([
            ui.heading("Build your monthly plan", 17),
            ui.label("Goal"), ui.chips(GOALS, st["goal"], lambda k: st.update(goal=k)),
            ui.label("Experience"), ui.chips(EXPERIENCE, st["experience"], lambda k: st.update(experience=k)),
            ui.label("Training days"), ui.multi_chips(WEEKDAYS, days),
            ui.label("Session length"), ui.chips(MINUTES, st["minutes"], lambda k: st.update(minutes=k)),
            ui.label("Equipment"), ui.chips(EQUIPMENT, st["equipment"], lambda k: st.update(equipment=k)),
            error, ui.button("Make my plan", go, icon=ft.Icons.AUTO_AWESOME, width=float("inf")),
        ], spacing=10), padding=16)

    def days_view(res, plan, *, offline=False, cached_at=None):
        today = res.get("today") or date.today().isoformat()
        coming = [d for d in plan.get("days", []) if d["day"] >= today][:7]

        def set_day(d, status):
            box.controls = [ui.loading()]
            app.page.update()

            def work():
                try:
                    app.api.call("training-plan", "POST", {"action": "set_day", "plan_id": plan["id"], "day": d["day"],
                                                           "status": status})
                except ApiError as ex:
                    if app.store.set_plan_day(d["day"], status):
                        app.toast("Plan progress saved on this device; it will refresh from the server when online.")
                    else:
                        app.toast(str(ex), error=True)
                load()
            app.run(work)

        rows: list[ft.Control] = []
        if offline:
            stamp = f" Last updated {ui.when(cached_at)}." if cached_at else ""
            stale = " This cache may be outdated; reconnect to refresh." if app.store.cache_is_stale(cached_at) else ""
            rows.append(ui.card(ft.Row([ft.Icon(ft.Icons.WIFI_OFF, color=ui.C.gold),
                                        ui.body(f"Offline mode · using your cached plan.{stamp}{stale}", size=12)]),
                                accent=ui.fade(ui.C.gold, 0x88)))
        rows.append(ui.body(f"{plan['start_date']} to {plan['end_date']}. "
                            + (plan.get("notes") or ""), size=12))
        for d in coming:
            rest = not d.get("workout")
            status = d.get("status", "planned")
            rows.append(ui.card(ft.Column([
                ft.Row([ui.heading(date.fromisoformat(d["day"]).strftime("%a %b %d") + (" · today" if d["day"] == today else ""), 15),
                        ft.Container(expand=True),
                        ui.tag("rest" if rest else status, ui.C.dim if rest else
                               {"done": ui.C.food, "skipped": ui.C.danger}.get(status, ui.C.accent))]),
                *([ui.body(d.get("session_name") or "", color=ui.C.text)] if not rest else []),
                *[ui.body(dose(x), size=13) for x in (d.get("workout") or [])],
                *([ft.Row([ui.button("Done", lambda e, d=d: set_day(d, "done"), icon=ft.Icons.CHECK, kind="food"),
                           ui.button("Skip", lambda e, d=d: set_day(d, "skipped"), kind="text")])] if not rest and status == "planned" else []),
            ], spacing=6), padding=12))
        rows.append(ft.Row([
            ui.button("Retake survey", lambda e: (box.controls.clear(), box.controls.append(survey(res)), app.page.update()),
                      kind="ghost"),
            *([ui.button("Start next month", lambda e: call({"action": "next_month"}), kind="accent")]
              if plan.get("next_month_available") else []),
        ], wrap=True))
        if res.get("credit"):
            rows.append(ui.body(res["credit"]["text"], size=11))
        return rows

    app.run(load)
    return ui.screen("Training plan", box, subtitle="A month of sessions built from your goal, days and equipment.")


def budget(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=10)
    daily = ui.number_field("Daily food budget (₱)", "", decimals=True, expand=True)

    def load():
        try:
            res = app.api.call("budget-assistant")
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        b, target = res.get("budget") or {}, res.get("protein_target") or {}
        daily.value = f"{b['daily_php']:g}" if b.get("daily_php") else ""
        priced = sorted((c for c in res.get("commodities", []) if (c.get("per_25g_protein") or {}).get("php") is not None),
                        key=lambda c: c["per_25g_protein"]["php"])
        box.controls = [
            ui.card(ft.Column([
                ft.Row([daily, ui.button("Save", save)], spacing=10),
                ui.body(f"Protein target: {round(target['grams'])} g a day." if target.get("grams") else
                        "Add your weight in your profile to get a protein target.", size=12),
            ], spacing=8), padding=14),
            ui.section("Cheapest protein (₱ per 25 g)"),
            *[ui.card(ft.Row([ft.Text(c["name"], color=ui.C.text, expand=True),
                              ft.Text(f"₱{c['per_25g_protein']['php']:.2f}", color=ui.C.food, font_family="LatoBold")]),
                      padding=10) for c in priced[:15]],
            *([] if priced else [ui.empty("No prices yet.", ft.Icons.SELL_OUTLINED)]),
            ui.body("Estimates from Philippine reference prices, not financial or dietary advice.", size=11),
        ]
        app.page.update()

    def save(e):
        def work():
            try:
                app.api.call("budget-assistant", "POST", {"action": "set_budget",
                                                          "daily_budget_php": float(daily.value) if daily.value else None})
                app.toast("Budget saved.")
            except ApiError as ex:
                app.toast(str(ex), error=True)
        app.run(work)

    app.run(load)
    return ui.screen("Food budget", box, subtitle="Eat enough protein on the money you have.")
