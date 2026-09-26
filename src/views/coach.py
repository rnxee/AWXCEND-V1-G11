"""AI coach: accept the AI notice once, then ask for advice based on recent training and meals."""
import flet as ft

import ui
from api import ApiError


def view(app) -> ft.Control:
    box = ft.Column([ui.loading()], spacing=14)
    notice: dict = {}

    def load():
        try:
            res = app.api.call("privacy")
        except ApiError as ex:
            box.controls = [ui.error_box(str(ex), lambda: app.run(load))]
            app.page.update()
            return
        notice.update((res.get("notices") or {}).get("ai_features") or {})
        latest = (res.get("latest") or {}).get("ai_features") or {}
        box.controls = [ask_card()] if latest.get("is_current") else [consent_card()]
        app.page.update()

    def consent_card():
        def accept(e):
            def work():
                try:
                    app.api.call("privacy", "POST", {"action": "acknowledge", "consent_type": "ai_features",
                                                     "notice_version": notice["version"]})
                except (ApiError, KeyError) as ex:
                    app.toast(str(ex) or "Couldn't save your choice.", error=True)
                    return
                box.controls = [ask_card()]
                app.page.update()
            app.run(work)

        return ui.card(ft.Column([
            ui.heading(notice.get("title", "AI features notice"), 16),
            ft.Container(ft.Markdown(notice.get("body", "")), height=280),
            ui.button("I understand - turn on the AI coach", accept, kind="accent"),
        ], spacing=12, scroll=ft.ScrollMode.AUTO), accent=ui.fade(ui.C.accent, 0x66))

    def ask_card():
        answer = ft.Column(spacing=12)
        ask_btn = ui.button("Get advice", None, icon=ft.Icons.AUTO_AWESOME, kind="accent", height=46)

        def ask(e):
            ask_btn.disabled = True
            answer.controls = [ui.loading("The coach is thinking... this can take up to a minute.")]
            app.page.update()
            app.run(work)

        def work():
            try:
                res = app.api.call("get-suggestions", "POST")
            except ApiError as ex:
                msg = str(ex)
                if ex.status == 502:
                    msg = "The AI server is offline right now. Try again later."
                elif ex.code == "CONSENT_REQUIRED":
                    box.controls = [consent_card()]
                answer.controls = [ui.error_box(msg)]
            else:
                answer.controls = [ui.card(ft.Markdown(res.get("suggestion_text") or "", selectable=True))]
                target, actual = res.get("macro_target"), res.get("macro_actual")
                if target and actual:
                    answer.controls.append(ui.card(ft.Column([ui.label("Today vs target")] + [
                        ft.Row([ft.Text(k.title(), color=ui.C.text, width=80),
                                ft.Container(ui.xp_bar((actual.get(k) or 0) / (target.get(k) or 1), ui.C.food), expand=True),
                                ui.body(f"{actual.get(k, 0)} / {round(target.get(k) or 0)}", size=12)])
                        for k in ("calories", "protein", "carbs", "fat") if target.get(k)], spacing=8)))
            ask_btn.disabled = False
            app.page.update()

        ask_btn.on_click = ask
        return ft.Column([
            ui.card(ft.Row([ft.Icon(ft.Icons.AUTO_AWESOME, color=ui.C.accent, size=32),
                            ui.body("Your coach reads your recent workouts and meals and suggests what to do next. "
                                    "It's general fitness advice, not medical advice.", color=ui.C.text, expand=True)],
                           spacing=14), accent=ui.fade(ui.C.accent, 0x66)),
            ask_btn, answer], spacing=14)

    app.run(load)
    return ui.screen("AI coach", box)
