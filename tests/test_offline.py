"""Offline-first local records and the durable synchronization queue."""
from pathlib import Path

from offline_store import OfflineStore


USER = "user-1"


def workout():
    return {"exercise": "squat", "sets": 3, "reps": 8, "weight_kg": 40.0, "workout_source": "manual"}


def meal():
    return {"logged_method": "manual_scale", "food_name": "Rice", "meal_period": "Lunch", "weight_g": 200,
            "calories": 260, "protein": 5, "carbs": 56, "fat": 0.5, "fiber": 1, "sugar": 0}


class FakeApi:
    def __init__(self, user_id=USER, responses=None, error=None):
        self.user_id = user_id
        self.responses = responses or {}
        self.error = error
        self.calls = []

    def call(self, fn, method, body):
        self.calls.append((fn, body))
        if self.error:
            raise self.error
        if fn == "log-workout":
            return {"success": True, "workout_log_id": "server-workout-1", "xp_earned": 24}
        return {"success": True, "log": {"id": "server-meal-1", **body}, "gold_awarded": 10}


class LostResponseApi(FakeApi):
    """The server commits the first call, but the client misses its response."""
    def __init__(self):
        super().__init__()
        self.committed = None

    def call(self, fn, method, body):
        if self.committed is None:
            self.committed = super().call(fn, method, body)
            raise RuntimeError("response lost")
        self.calls.append((fn, body))
        return self.committed


class ExpiringApi(FakeApi):
    def call(self, fn, method, body):
        self.calls.append((fn, body))
        self.user_id = None
        raise RuntimeError("session expired")


def test_workout_is_available_and_survives_store_reinitialization(tmp_path: Path):
    path = tmp_path / "offline.json"
    store = OfflineStore(file_path=path)
    store.set_account(USER)
    saved = store.add_workout(workout())

    reopened = OfflineStore(file_path=path)
    reopened.set_account(USER)
    records = reopened.list_workouts()
    assert records[0]["local_id"] == saved["local_id"]
    assert records[0]["sync_status"] == "pending"
    assert reopened.queue_size() == 1


def test_sync_keeps_failed_records_and_retries_without_duplicates(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    local = store.add_workout(workout())

    failed = store.sync(FakeApi(error=RuntimeError("offline")), force=True)
    assert failed == {"synced": 0, "failed": 1, "pending": 1}
    assert store.list_workouts()[0]["sync_status"] == "failed"

    api = FakeApi()
    synced = store.sync(api, force=True)
    assert synced == {"synced": 1, "failed": 0, "pending": 0}
    assert len(api.calls) == 1
    record = store.list_workouts()[0]
    assert record["server_id"] == "server-workout-1" and record["xp_earned"] == 24

    # A second retry has no queue item, so it cannot create a duplicate.
    assert store.sync(api, force=True) == {"synced": 0, "failed": 0, "pending": 0}
    assert local["client_request_id"] == api.calls[0][1]["client_request_id"]


def test_lost_response_reuses_the_same_request_id_on_retry(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    store.add_workout(workout())
    api = LostResponseApi()
    assert store.sync(api, force=True)["failed"] == 1
    assert store.sync(api, force=True)["synced"] == 1
    assert api.calls[0][1]["client_request_id"] == api.calls[1][1]["client_request_id"]
    assert store.queue_size() == 0


def test_pending_workout_edit_replaces_the_existing_upload(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    saved = store.add_workout(workout())
    edited = store.edit_workout(saved["local_id"], {"sets": 4, "reps": 6, "weight_kg": 45.0})
    assert edited["sets"] == 4 and edited["reps"] == 6
    api = FakeApi()
    store.sync(api, force=True)
    assert len(api.calls) == 1
    assert api.calls[0][1]["sets"] == 4 and api.calls[0][1]["reps"] == 6


def test_retry_backoff_is_respected_unless_manually_forced(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    store.add_workout(workout())
    store.sync(FakeApi(error=RuntimeError("offline")), force=True, now=100)
    api = FakeApi()
    assert store.sync(api, now=104) == {"synced": 0, "failed": 0, "pending": 1}
    assert api.calls == []
    assert store.sync(api, now=105) == {"synced": 1, "failed": 0, "pending": 0}


def test_session_expiry_stops_before_sending_the_next_account_record(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    store.add_workout(workout())
    store.add_workout({**workout(), "exercise": "deadlift"})
    api = ExpiringApi()
    result = store.sync(api, force=True)
    assert result["failed"] == 1 and result["pending"] == 2
    assert len(api.calls) == 1


def test_meal_keeps_a_nutrition_snapshot_and_never_crosses_accounts(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    saved = store.add_meal(meal())
    assert saved["nutrition_snapshot"]["nutrition"]["calories"] == 260

    other = FakeApi(user_id="user-2")
    assert store.sync(other, force=True) == {"synced": 0, "failed": 0, "pending": 1}
    assert other.calls == []

    reopened = OfflineStore(file_path=tmp_path / "offline.json")
    reopened.set_account(USER)
    assert reopened.list_meals()[0]["nutrition_snapshot"]["nutrition"]["protein"] == 5


def test_cached_routines_and_plans_survive_restart(tmp_path: Path):
    path = tmp_path / "offline.json"
    store = OfflineStore(file_path=path)
    store.set_account(USER)
    store.cache_routines([{"id": "routine-1", "name": "Leg day", "routine_exercises": []}])
    store.cache_plan({"today": "2026-10-25", "plan": {"id": "plan-1", "days": []}})

    reopened = OfflineStore(file_path=path)
    reopened.set_account(USER)
    routines, routine_stamp = reopened.cached_routines()
    plan, plan_stamp = reopened.cached_plan()
    assert routines[0]["name"] == "Leg day" and routine_stamp
    assert plan["plan"]["id"] == "plan-1" and plan_stamp


def test_older_routine_response_does_not_replace_newer_cache(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    store.cache_routines([{"id": "routine-1", "name": "New name", "updated_at": "2026-10-25T12:00:00+00:00"}])
    store.cache_routines([{"id": "routine-1", "name": "Old name", "updated_at": "2026-10-25T11:00:00+00:00"}])
    routines, _ = store.cached_routines()
    assert routines[0]["name"] == "New name"


def test_local_plan_progress_is_not_overwritten_by_an_older_response(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    plan = {"plan": {"id": "plan-1", "days": [{"day": "2026-10-25", "status": "planned"}]}}
    store.cache_plan(plan)
    assert store.set_plan_day("2026-10-25", "done")
    store.cache_plan(plan)
    cached, _ = store.cached_plan()
    assert cached["plan"]["days"][0]["status"] == "done"


def test_cached_food_can_be_reused_for_an_offline_meal(tmp_path: Path):
    store = OfflineStore(file_path=tmp_path / "offline.json")
    store.set_account(USER)
    item = {"food": {"food_id": "food-1", "name": "Rice",
                      "nutrition": {"calories": 130, "protein": 2.7, "carbs": 28, "fat": 0.3}},
            "servings": [{"label": "bowl", "grams": 200}]}
    store.cache_foods([item])
    cached = store.cached_foods("rice")
    logged = store.add_meal({"logged_method": "manual_scale", "food_name": cached[0]["food"]["name"],
                             "meal_period": "Lunch", "weight_g": 200, "calories": 260,
                             "protein": 5.4, "carbs": 56, "fat": 0.6})
    assert cached[0]["food"]["nutrition"]["calories"] == 130
    assert logged["nutrition_snapshot"]["nutrition"]["calories"] == 260


def test_malformed_storage_starts_empty(tmp_path: Path):
    path = tmp_path / "offline.json"
    path.write_text("not-json", encoding="utf-8")
    store = OfflineStore(file_path=path)
    store.set_account(USER)
    assert store.list_workouts() == [] and store.list_meals() == []


def test_malformed_record_lists_are_ignored(tmp_path: Path):
    path = tmp_path / "offline.json"
    path.write_text('{"accounts":{"user-1":{"workouts":["bad", null],"queue":[3]}}}', encoding="utf-8")
    store = OfflineStore(file_path=path)
    store.set_account(USER)
    assert store.list_workouts() == [] and store.queue_size() == 0

