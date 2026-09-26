"""Food tab: today's totals, food search (per-100 g nutrition), log a portion, recent meals."""
from datetime import datetime

import flet as ft

import ui
from api import ApiError

PERIODS = ["Breakfast", "Lunch", "Dinner", "Snack"]
MACROS = ("calories", "protein", "carbs", "fat", "fiber", "sugar")


def default_period(hour: int) -> str:
    return "Breakfast" if hour < 10 else "Lunch" if hour < 15 else "Dinner" if hour < 21 else "Snack"


def portion(per_100g: dict, grams: float) -> dict:
    return {k: round((per_100g.get(k) or 0) * grams / 100, 1) for k in MACROS}


def _is_today(iso: str) -> bool:
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone().date() == datetime.now().date()
    except (ValueError, AttributeError):
        return False


def view(app) -> ft.Control:
    totals = ft.Row(spacing=10)
    logs_box = ft.Column([ui.loading()], spacing=10)
    results = ft.Column(spacing=8)
    search = ui.field("Search foods (e.g. chicken breast, kanin)", prefix_icon=ft.Icons.SEARCH, expand=True)

    def load_logs():
        try:
            logs = app.api.call("get-meal-logs").get("logs", [])
        except ApiError as ex:
            logs_box.controls = [ui.error_box(str(ex), lambda: app.run(load_logs))]
            app.page.update()
            return
        today = [l for l in logs if _is_today(l.get("logged_at", ""))]
        sums = {k: sum(float(l.get(k) or 0) for l in today) for k in ("calories", "protein", "carbs", "fat")}
        totals.controls = [
            ui.stat("kcal", round(sums["calories"]), ui.C.gold),
            ui.stat("Protein", f"{sums['protein']:.0f} g", ui.C.food),
            ui.stat("Carbs", f"{sums['carbs']:.0f} g", ui.C.primary_bright),
            ui.stat("Fat", f"{sums['fat']:.0f} g", ui.C.accent),
        ]
        logs_box.controls = [
            ui.card(ft.Row([
                ft.Column([ft.Text(l.get("food_name", ""), color=ui.C.text, font_family="LatoBold"),
                           ui.body(f"{l.get('meal_period', '')} · {float(l.get('weight_g') or 0):g} g", size=12)],
                          spacing=2, expand=True),
                ft.Text(f"{round(float(l.get('calories') or 0))} kcal", color=ui.C.gold),
            ]), padding=12)
            for l in logs[:15]
        ] or [ui.empty("No meals logged yet.", ft.Icons.RESTAURANT)]
        app.page.update()

    def do_search(e=None):
        q = search.value.strip()
        if len(q) < 2:
            return
        results.controls = [ui.loading("Searching...")]
        app.page.update()
        app.run(search_work, q)

    def search_work(q):
        try:
            items = app.api.call("search-food", params={"query": q}).get("results", [])
        except ApiError as ex:
            results.controls = [ui.error_box(str(ex))]
            app.page.update()
            return
        results.controls = [result_row(it) for it in items] or [ui.empty(f"No foods found for “{q}”.", ft.Icons.SEARCH_OFF)]
        app.page.update()

    def result_row(item):
        f = item["food"]
        n = f.get("nutrition") or {}
        tag = "estimate" if f.get("is_estimate") else (f.get("source") or "")
        return ui.card(ft.Row([
            ft.Column([ft.Text(f.get("name", ""), color=ui.C.text, font_family="LatoBold"),
                       ui.body(f"{round(n.get('calories') or 0)} kcal · {round(n.get('protein') or 0)} g protein per 100 g"
                               + (f" · {tag}" if tag else ""), size=12)], spacing=2, expand=True),
            ft.Icon(ft.Icons.ADD_CIRCLE_OUTLINE, color=ui.C.food),
        ]), padding=12, on_click=lambda e: log_dialog(item))

    def log_dialog(item):
        f = item["food"]
        per100 = f.get("nutrition") or {}
        servings = item.get("servings") or []
        grams = ui.number_field("Amount (g)", servings[0]["grams"] if servings else 100, decimals=True, expand=True)
        period = ui.dropdown("Meal", [(p, p) for p in PERIODS], default_period(datetime.now().hour), expand=True)
        chosen = {"label": servings[0]["label"] if servings else None}

        def summary() -> str:
            m = portion(per100, float(grams.value or 0))
            return f"{m['calories']:.0f} kcal · P {m['protein']:g} g · C {m['carbs']:g} g · F {m['fat']:g} g"

        preview = ui.body(summary(), color=ui.C.text)

        def refresh(e=None):
            preview.value = summary()
            preview.update()

        def pick_serving(label):
            s = next(s for s in servings if s["label"] == label)
            chosen["label"] = label
            grams.value = f"{s['grams']:g}"
            grams.update()
            refresh()

        grams.on_change = refresh

        def save(e):
            g = float(grams.value or 0)
            if not 0 < g <= 5000:
                app.toast("Amount must be between 1 and 5000 g.", error=True)
                return
            body = {"logged_method": "manual_scale", "food_name": f["name"][:200], "meal_period": period.value,
                    "weight_g": g, **portion(per100, g)}
            if f.get("food_id"):
                body["food_id"] = f["food_id"]
            elif f.get("usda_fdc_id"):
                body["usda_fdc_id"] = int(f["usda_fdc_id"])
            if chosen["label"]:
                body["serving_label"] = chosen["label"]
            app.page.pop_dialog()
            app.run(save_work, body)

        rows = [ui.body(f"Per 100 g: {round(per100.get('calories') or 0)} kcal", size=12)]
        if servings:
            rows.append(ui.chips([(s["label"], f"{s['label']} ({s['grams']:g} g)") for s in servings[:6]],
                                 servings[0]["label"], pick_serving))
        rows += [ft.Row([grams, period], spacing=10), preview]
        dlg = ft.AlertDialog(title=ft.Text(f["name"]), content=ft.Column(rows, tight=True, spacing=12, width=440),
                             actions=[ui.button("Cancel", lambda e: app.page.pop_dialog(), kind="text"),
                                      ui.button("Log meal", save, icon=ft.Icons.CHECK, kind="food")])
        app.page.show_dialog(dlg)

    def save_work(body):
        try:
            res = app.api.call("log-meal", "POST", body)
        except ApiError as ex:
            app.toast(str(ex), error=True)
            return
        gold = res.get("gold_awarded")
        app.toast(f"Logged {body['food_name']}" + (f" · +{gold} gold" if gold else ""))
        load_logs()

    search.on_submit = do_search
    app.run(load_logs)
    return ui.screen(
        "Food", ui.label("Today"), totals,
        ft.Row([search, ft.IconButton(ft.Icons.SEARCH, on_click=do_search, tooltip="Search")]),
        results, ui.label("Recent meals"), logs_box,
        subtitle="Nutrition values are estimates. Log what you ate to track your macros.",
    )
