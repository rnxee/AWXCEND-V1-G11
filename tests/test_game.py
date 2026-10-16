"""Missions, the training plan survey and the shop: what the screens send and show."""
import json

import httpx
from flet.controls.base_control import BaseControl

from fakes import FakeApp, button, fields, walk
from views import game, plan

MISSION = {"id": "m1", "name": "Rust Gate", "boss_name": "Rust Gremlin", "boss_lore": "",
           "objectives": [{"sequence": 1, "exercise": "squat", "metric_type": "reps", "target_value": 15}]}


def test_survey_answers_and_doses():
    assert plan.survey_answers("muscle", "new", ["fri", "mon"], "45", "gym") == {
        "goal": "muscle", "experience": "new", "days": ["mon", "fri"], "minutes": 45, "equipment": "gym",
        "preferCamera": False}
    assert "2 to 6" in plan.survey_answers("muscle", "new", ["mon"], "45", "gym")
    assert plan.dose({"label": "Plank", "sets": 3, "seconds": 40}) == "Plank · 3 × 40 s"
    assert game.target_text(MISSION["objectives"][0]) == "Squat · 15 reps"


def test_a_mission_is_played_with_manual_sets():
    sent = []

    def handler(req):
        body = json.loads(req.content)
        sent.append(body["action"])
        if body["action"] == "start":
            return httpx.Response(200, json={"success": True, "attempt_id": "a1", "boss_hp": 100, "max_hp": 100,
                                             "current_sequence": 1, "objectives": MISSION["objectives"]})
        if body["action"] == "submit":
            assert body == {"action": "submit", "attempt_id": "a1", "achieved": 16, "workout_source": "manual"}
            return httpx.Response(200, json={"success": True, "mission_complete": True, "grade": "C", "first_clear": True,
                                             "boss_hp": 0, "max_hp": 100, "rewards": {"xp": 50, "gold": 20}})
        return httpx.Response(200, json={"success": True})

    app = FakeApp(handler, profile={"username": "ash"})
    original, BaseControl.update = BaseControl.update, lambda self: None
    try:
        screen = game.fight(app, MISSION)
        button(screen, "Start mission").on_click(None)
        button(screen, "Begin set").on_click(None)  # starts the server's timer before the set
        fields(screen)["Reps (or seconds) you did"].value = "16"
        button(screen, "Submit").on_click(None)
    finally:
        BaseControl.update = original
    assert sent == ["start", "objective_start", "submit"]
    texts = [getattr(c, "value", None) for c in walk(screen)]
    assert "Mission cleared!" in texts and "Grade C · +50 XP · +20 gold" in texts


def test_buying_sends_a_fresh_request_id_each_time():
    bought = []

    def handler(req):
        if req.method == "POST":
            bought.append(json.loads(req.content))
            return httpx.Response(200, json={"success": True})
        return httpx.Response(200, json={"success": True, "balance": 500, "items": [
            {"key": "streak_restore", "name": "Streak Restore", "description": "", "price_gold": 300,
             "max_stack": 2, "scope": "global", "owned": 0}]})

    app = FakeApp(handler, profile={"username": "ash"})
    screen = game.shop(app)
    button(screen, "Buy").on_click(None)
    button(screen, "Buy").on_click(None)
    assert [b["item_key"] for b in bought] == ["streak_restore", "streak_restore"]
    assert bought[0]["request_id"] != bought[1]["request_id"]  # a double-tap on one press is charged once server-side
