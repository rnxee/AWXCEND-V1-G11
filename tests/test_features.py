"""Routines, the strength board, admin sections by role, and deleting an account."""
import json

import httpx
import pytest

from fakes import FakeApp, button, fields
from views import account, admin, routines
from views.social import strength_detail, strength_value

SESSION = {"access_token": "tok", "refresh_token": "ref", "user": {"id": "u1"}}


def test_routine_payload():
    assert routines.payload(" Push day ", "", [("benchpress", "3", "10"), ("plank", "2", "60")]) == {
        "name": "Push day", "notes": None, "exercises": [
            {"exercise": "benchpress", "target_sets": 3, "target_reps": 10},
            {"exercise": "plank", "target_sets": 2, "target_duration_seconds": 60}]}
    assert routines.payload("", "", [("squat", "3", "5")]) == "Give the routine a name."
    assert "row 1" in routines.payload("Legs", "", [("not-an-exercise", "3", "5")])
    assert "reps must be 1-300" in routines.payload("Legs", "", [("squat", "3", "500")])
    assert routines.payload("Legs", "", []) == "Add at least one exercise."
    assert routines.target_text({"target_sets": 3, "target_duration_seconds": 75}) == "3 × 1:15"


def test_a_timed_routine_exercise_logs_its_total_time():
    import flet as ft

    from fakes import walk
    logged = []

    def handler(req):
        if req.url.path == "/functions/v1/log-workout":
            logged.append(json.loads(req.content))
            return httpx.Response(200, json={"xp_earned": 12})
        return httpx.Response(200, json={"profile": {}})

    app = FakeApp(handler, profile={"username": "ash"})
    routine = {"name": "Core", "routine_exercises": [{"exercise": "plank", "target_sets": 3,
                                                       "target_duration_seconds": 60}]}
    screen = routines.run(app, routine)
    next(c for c in walk(screen) if isinstance(c, ft.Container) and c.on_click).on_click(None)  # tap the plank
    button(app.dialogs[-1], "Log").on_click(None)
    assert logged == [{"exercise": "plank", "duration_seconds": 180, "workout_source": "manual"}]


def test_sanction_durations_and_preview():
    from views.sanctions import duration_body, preview
    assert duration_body("7d") == {"amount": 7, "unit": "days"}
    assert duration_body("1h") == {"amount": 1, "unit": "hours"}
    assert duration_body("forever") == {"permanent": True}
    assert preview("ban", [], "forever", "Spam") == "Account suspended permanently. Reason: Spam"
    assert preview("restrict", ["chat", "dm"], "30d", "Insults") == \
        "You can't use community chat, direct messages for 30 days. Reason: Insults"


def test_sanctioning_from_a_report_sends_what_the_moderator_chose():
    from flet.controls.base_control import BaseControl

    from views.sanctions import issue_dialog
    sent = []

    def handler(req):
        sent.append(json.loads(req.content))
        return httpx.Response(200, json={"success": True})

    app = FakeApp(handler, profile={"role": "moderator"})
    issue_dialog(app, {"id": "u9", "username": "Troll99"}, report_id="r1")
    dialog = app.dialogs[-1]
    original, BaseControl.update = BaseControl.update, lambda self: None  # no page in a unit test
    try:
        button(dialog, "Apply").on_click(None)  # no reason yet: refused locally
        assert sent == [] and app.dialogs == [dialog]
        fields(dialog)["Reason (they see it)"].value = "Insults in chat"
        button(dialog, "Apply").on_click(None)
    finally:
        BaseControl.update = original
    assert sent == [{"action": "issue", "user_id": "u9", "kind": "restrict", "privileges": ["chat"],
                     "reason": "Insults in chat", "amount": 1, "unit": "days", "report_id": "r1"}]
    assert app.toasts == ["Troll99 is restricted."]


def test_which_workouts_can_be_deleted():
    from datetime import datetime, timezone

    from views.home import deletable
    now = datetime(2026, 10, 16, 12, 0, tzinfo=timezone.utc)
    recent = {"id": "w1", "workout_source": "manual", "logged_at": "2026-10-16T02:00:00.123"}  # naive UTC, 10 h ago
    assert deletable(recent, now)
    assert not deletable({**recent, "logged_at": "2026-10-15T11:59:00"}, now)  # just over 24 h
    assert not deletable({**recent, "workout_source": "camera"}, now)
    assert not deletable({**recent, "id": None}, now)


def test_deleting_a_workout_and_a_meal():
    from flet.controls.base_control import BaseControl

    from views import food
    from views.home import confirm_delete_workout
    sent = []

    def handler(req):
        if req.method == "POST":
            sent.append((req.url.path.rsplit("/", 1)[-1], json.loads(req.content)))
            return httpx.Response(200, json={"success": True, "xp_removed": 42})
        if req.url.path.endswith("get-meal-logs"):
            return httpx.Response(200, json={"logs": [{"id": "meal1", "food_name": "Rice", "calories": 260}]})
        return httpx.Response(200, json={"profile": {}})

    app = FakeApp(handler, profile={"username": "ash"})
    done = []
    confirm_delete_workout(app, {"id": "w1", "exercise": "squat", "sets": 3, "reps": 5, "xp_earned": 42},
                           lambda: done.append(True))
    button(app.dialogs[-1], "Delete").on_click(None)
    original, BaseControl.update = BaseControl.update, lambda self: None
    try:
        screen = food.view(app)
        from fakes import walk
        next(c for c in walk(screen) if getattr(c, "tooltip", None) == "Delete meal").on_click(None)
        button(app.dialogs[-1], "Delete").on_click(None)
    finally:
        BaseControl.update = original
    assert sent == [("delete-workout", {"workout_log_id": "w1"}), ("delete-meal", {"meal_log_id": "meal1"})]
    assert done == [True] and app.toasts == ["Workout deleted · −42 XP", "Meal deleted."]


def test_strength_board_lines():
    r = {"e1rm_kg": 142.6, "relative_e1rm": 1.83, "weight_kg": 120.0, "reps": 5, "strength_rank": "Warrior 3",
         "form_verified": True}
    assert strength_value(r, False) == "143 kg" and strength_value(r, True) == "1.83× BW"
    assert strength_detail(r) == "120 kg × 5 · Warrior 3 · form ✓"
    assert strength_value({**r, "relative_e1rm": None}, True) == "–"


@pytest.mark.parametrize("role,sections", [
    ("moderator", ["reports", "posts", "bugs", "sanctions"]),
    ("admin", ["reports", "posts", "bugs", "sanctions", "users", "audit"]),
    ("user", []),
])
def test_admin_sections_follow_the_server_permissions(role, sections):
    assert [k for k, _, roles in admin.SECTIONS if role in roles] == sections


def deleting(delete_response: httpx.Response):
    sent = []

    def handler(req):
        if req.url.path == "/functions/v1/delete-account":
            sent.append(json.loads(req.content))
            return delete_response
        return httpx.Response(200, json={"success": True, "notices": {}})  # privacy, for the screen

    app = FakeApp(handler, profile={"username": "ash"})
    app.api.set_session(SESSION)
    screen = account.view(app)
    button(screen, "Delete my account").on_click(None)
    dialog = app.dialogs[-1]
    form = fields(dialog)
    form["Type your username (ash)"].value, form["Password"].value = "ash", "pw123456"
    button(dialog, "Delete forever").on_click(None)
    return app, dialog, sent


def test_a_refused_delete_keeps_you_signed_in_with_the_reason_shown():
    app, dialog, sent = deleting(httpx.Response(401, json={"success": False, "errors": ["Incorrect password."]}))
    assert sent == [{"confirm_username": "ash", "password": "pw123456"}]
    assert app.dialogs == [dialog] and app.screens == [] and app.api.session is not None
    assert any(getattr(c, "value", None) == "Incorrect password." for c in dialog.content.controls)


def test_a_deleted_account_is_signed_out():
    app, _, sent = deleting(httpx.Response(200, json={"success": True}))
    assert len(sent) == 1 and app.dialogs == [] and app.screens == ["login"]
    assert app.api.session is None and app.saved[-1] is None
