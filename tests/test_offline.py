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

