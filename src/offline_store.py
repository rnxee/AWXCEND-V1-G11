from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import os
from threading import RLock
from time import time
from typing import Any, Callable
from uuid import uuid4


STORE_VERSION = 1
SYNC_BACKOFF_SECONDS = 5
MAX_SYNC_BACKOFF_SECONDS = 3600


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _empty_account() -> dict[str, Any]:
    return {
        "workouts": [],
        "meals": [],
        "routines": [],
        "plans": [],
        "foods": [],
        "queue": [],
    }


class OfflineStore:
    """A small JSON-backed local database with one namespace per account.

    ``file_path`` is useful for desktop/test use.  The Flet app passes a
    ``persist`` callback instead, because SharedPreferences is the portable
    application-data store on the project's Windows and Android targets.
    """

    def __init__(self, data: dict[str, Any] | None = None,
                 *, file_path: str | Path | None = None,
                 persist: Callable[[str], None] | None = None):
        self._lock = RLock()
        self.file_path = Path(file_path) if file_path else None
        self.persist = persist
        self.account_id: str | None = None
        self._data = self._normalise(data if data is not None else self._read_file())

    @staticmethod
    def _normalise(raw: Any) -> dict[str, Any]:
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except (TypeError, ValueError):
                raw = {}
        if not isinstance(raw, dict):
            raw = {}
        accounts = raw.get("accounts")
        if not isinstance(accounts, dict):
            accounts = {}
        clean: dict[str, Any] = {"version": STORE_VERSION, "accounts": {}}
        for user_id, account in accounts.items():
            if not isinstance(user_id, str) or not isinstance(account, dict):
                continue
            base = _empty_account()
            for key in base:
                value = account.get(key)
                if isinstance(value, list):
                    base[key] = value
            clean["accounts"][user_id] = base
        return clean

    def _read_file(self) -> Any:
        if not self.file_path or not self.file_path.exists():
            return {}
        try:
            return json.loads(self.file_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            # A damaged cache must never prevent the app from opening.  The
            # corrupt file is left in place for diagnostics/recovery.
            return {}

    def restore(self, raw: Any) -> None:
        with self._lock:
            self._data = self._normalise(raw)
            self._write()

    def export(self) -> dict[str, Any]:
        with self._lock:
            return deepcopy(self._data)

    def set_account(self, user_id: str | None) -> None:
        with self._lock:
            self.account_id = user_id
            if user_id:
                self._data["accounts"].setdefault(user_id, _empty_account())
                self._write()

    def _account(self, user_id: str | None = None) -> dict[str, Any]:
        uid = user_id or self.account_id
        if not uid:
            raise ValueError("An authenticated account is required for local data")
        return self._data["accounts"].setdefault(uid, _empty_account())

    def _write(self) -> None:
        raw = json.dumps(self._data, ensure_ascii=False, separators=(",", ":"))
        if self.file_path:
            self.file_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.file_path.with_suffix(self.file_path.suffix + ".tmp")
            try:
                temporary.write_text(raw, encoding="utf-8")
                os.replace(temporary, self.file_path)
            except OSError:
                try:
                    temporary.unlink(missing_ok=True)
                except OSError:
                    pass
        if self.persist:
            self.persist(raw)

    def _touch(self) -> None:
        self._write()

    # ---- local workout and meal records ------------------------------------
    def add_workout(self, payload: dict[str, Any], user_id: str | None = None) -> dict[str, Any]:
        with self._lock:
            local_id = f"local-{uuid4()}"
            request_id = str(uuid4())
            record = {
                **deepcopy(payload),
                "id": local_id,
                "local_id": local_id,
                "client_request_id": request_id,
                "logged_at": payload.get("logged_at") or now_iso(),
                "workout_source": payload.get("workout_source", "manual"),
                "xp_earned": None,
                "sync_status": "pending",
                "sync_error": None,
            }
            account = self._account(user_id)
            account["workouts"].insert(0, record)
            self._queue(account, "workout", local_id, request_id, payload)
            self._touch()
            return deepcopy(record)

    def add_meal(self, payload: dict[str, Any], user_id: str | None = None) -> dict[str, Any]:
        with self._lock:
            local_id = f"local-{uuid4()}"
            request_id = str(uuid4())
            snapshot = deepcopy(payload.get("nutrition_snapshot") or {
                "food_name": payload.get("food_name"),
                "nutrition": {k: payload.get(k) for k in
                               ("calories", "protein", "carbs", "fat", "fiber", "sugar")},
            })
            record = {
                **deepcopy(payload),
                "id": local_id,
                "local_id": local_id,
                "client_request_id": request_id,
                "logged_at": payload.get("logged_at") or now_iso(),
                "nutrition_snapshot": snapshot,
                "sync_status": "pending",
                "sync_error": None,
            }
            account = self._account(user_id)
            account["meals"].insert(0, record)
            self._queue(account, "meal", local_id, request_id, payload)
            self._touch()
            return deepcopy(record)

    def list_workouts(self, user_id: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            return deepcopy(self._account(user_id)["workouts"])

    def list_meals(self, user_id: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            return deepcopy(self._account(user_id)["meals"])

    def delete_workout(self, local_id: str, user_id: str | None = None) -> bool:
        """Delete an unsynchronized local workout and its pending upload."""
        with self._lock:
            account = self._account(user_id)
            before = len(account["workouts"])
            account["workouts"] = [x for x in account["workouts"] if x.get("local_id") != local_id]
            account["queue"] = [x for x in account["queue"] if x.get("local_id") != local_id]
            changed = len(account["workouts"]) != before
            if changed:
                self._touch()
            return changed

    def _find(self, collection: str, local_id: str, account: dict[str, Any]) -> dict[str, Any] | None:
        return next((row for row in account[collection] if row.get("local_id") == local_id), None)

    def _queue(self, account: dict[str, Any], kind: str, local_id: str,
               request_id: str, payload: dict[str, Any]) -> None:
        account["queue"].append({
            "kind": kind,
            "local_id": local_id,
            "request_id": request_id,
            "payload": deepcopy(payload),
            "attempts": 0,
            "next_attempt_at": 0.0,
            "last_error": None,
        })

    def queue_size(self, user_id: str | None = None) -> int:
        with self._lock:
            return len(self._account(user_id)["queue"])

    # ---- cached read-only data ----------------------------------------------
    def cache_foods(self, items: list[dict[str, Any]], user_id: str | None = None) -> None:
        with self._lock:
            account = self._account(user_id)
            by_key = {self._food_key(item): item for item in account["foods"]}
            for item in items:
                if isinstance(item, dict):
                    by_key[self._food_key(item)] = deepcopy(item)
            account["foods"] = list(by_key.values())[:200]
            self._touch()

    def cached_foods(self, query: str = "", user_id: str | None = None) -> list[dict[str, Any]]:
        q = query.strip().casefold()
        with self._lock:
            foods = self._account(user_id)["foods"]
            return deepcopy([x for x in foods if not q or q in str((x.get("food") or {}).get("name", x.get("name", ""))).casefold()])

    @staticmethod
    def _food_key(item: dict[str, Any]) -> str:
        food = item.get("food") if isinstance(item.get("food"), dict) else item
        return str(food.get("food_id") or food.get("usda_fdc_id") or food.get("name", "")).casefold()

    def cache_routines(self, routines: list[dict[str, Any]], user_id: str | None = None) -> None:
        with self._lock:
            account = self._account(user_id)
            account["routines"] = [{**deepcopy(r), "cached_at": now_iso()} for r in routines if isinstance(r, dict)]
            self._touch()

    def cached_routines(self, user_id: str | None = None) -> tuple[list[dict[str, Any]], str | None]:
        with self._lock:
            rows = deepcopy(self._account(user_id)["routines"])
            stamp = max((r.get("cached_at") for r in rows if r.get("cached_at")), default=None)
            return rows, stamp

    def cache_plan(self, response: dict[str, Any], user_id: str | None = None) -> None:
        with self._lock:
            self._account(user_id)["plans"] = [{"response": deepcopy(response), "cached_at": now_iso()}]
            self._touch()

    def cached_plan(self, user_id: str | None = None) -> tuple[dict[str, Any] | None, str | None]:
        with self._lock:
            rows = self._account(user_id)["plans"]
            if not rows or not isinstance(rows[0], dict):
                return None, None
            return deepcopy(rows[0].get("response")), rows[0].get("cached_at")

    def set_plan_day(self, day: str, status: str, user_id: str | None = None) -> bool:
        with self._lock:
            account = self._account(user_id)
            if not account["plans"] or not isinstance(account["plans"][0].get("response"), dict):
                return False
            response = account["plans"][0]["response"]
            plan = response.get("plan") or {}
            changed = False
            for item in plan.get("days", []):
                if item.get("day") == day:
                    item["status"] = status
                    changed = True
                    break
            if changed:
                self._touch()
            return changed

    # ---- server merge and synchronization ----------------------------------
    def merge_workouts(self, remote: list[dict[str, Any]], user_id: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            account = self._account(user_id)
            local = account["workouts"]
            by_server = {r.get("server_id") or r.get("id"): r for r in local if r.get("server_id") or r.get("sync_status") == "synced"}
            for row in remote or []:
                rid = row.get("id")
                if rid in by_server:
                    by_server[rid].update(deepcopy(row), sync_status="synced", sync_error=None)
                elif rid and not any(r.get("id") == rid for r in local):
                    local.append({**deepcopy(row), "server_id": rid, "sync_status": "synced", "local_id": f"remote-{rid}"})
            self._touch()
            return deepcopy(sorted(local, key=lambda r: r.get("logged_at", ""), reverse=True))

    def merge_meals(self, remote: list[dict[str, Any]], user_id: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            account = self._account(user_id)
            local = account["meals"]
            by_server = {r.get("server_id") or r.get("id"): r for r in local if r.get("server_id") or r.get("sync_status") == "synced"}
            for row in remote or []:
                rid = row.get("id")
                if rid in by_server:
                    by_server[rid].update(deepcopy(row), sync_status="synced", sync_error=None)
                elif rid and not any(r.get("id") == rid for r in local):
                    local.append({**deepcopy(row), "server_id": rid, "sync_status": "synced", "local_id": f"remote-{rid}",
                                  "nutrition_snapshot": row.get("nutrition_snapshot")})
            self._touch()
            return deepcopy(sorted(local, key=lambda r: r.get("logged_at", ""), reverse=True))

    @staticmethod
    def _request_payload(item: dict[str, Any], request_id: str) -> dict[str, Any]:
        payload = deepcopy(item)
        for key in ("id", "local_id", "server_id", "client_request_id", "logged_at", "sync_status", "sync_error",
                    "nutrition_snapshot"):
            payload.pop(key, None)
        payload["client_request_id"] = request_id
        return payload

    def sync(self, api: Any, *, force: bool = False, user_id: str | None = None,
             now: float | None = None) -> dict[str, int]:
        """Upload this account's queue serially; retain every failed item.

        The API client's current user must still be the account that created the
        queue.  This guard is intentional: a stale local queue must never be
        sent after a sign-out/account switch.
        """
        with self._lock:
            uid = user_id or self.account_id
            if not uid or getattr(api, "user_id", None) != uid:
                return {"synced": 0, "failed": 0, "pending": self.queue_size(uid) if uid else 0}
            account = self._account(uid)
            queue = list(account["queue"])
        clock = time() if now is None else now
        result = {"synced": 0, "failed": 0, "pending": len(queue)}
        for operation in queue:
            if not force and float(operation.get("next_attempt_at") or 0) > clock:
                continue
            kind = operation.get("kind")
            fn = "log-workout" if kind == "workout" else "log-meal" if kind == "meal" else None
            if not fn:
                continue
            payload = self._request_payload(operation.get("payload") or {}, operation["request_id"])
            try:
                response = api.call(fn, "POST", payload)
            except Exception as exc:  # ApiError is kept optional for pure unit tests.
                self._mark_failed(uid, operation["local_id"], operation["request_id"], str(exc), clock)
                result["failed"] += 1
                continue
            self._mark_synced(uid, operation, response or {})
            result["synced"] += 1
        result["pending"] = self.queue_size(uid)
        return result

    def _mark_failed(self, user_id: str, local_id: str, request_id: str, error: str, clock: float) -> None:
        with self._lock:
            account = self._account(user_id)
            operation = next((x for x in account["queue"] if x.get("request_id") == request_id), None)
            if not operation:
                return
            operation["attempts"] = int(operation.get("attempts") or 0) + 1
            operation["last_error"] = error[:500]
            operation["next_attempt_at"] = clock + min(MAX_SYNC_BACKOFF_SECONDS,
                                                       SYNC_BACKOFF_SECONDS * (2 ** min(operation["attempts"] - 1, 8)))
            collection = "workouts" if operation.get("kind") == "workout" else "meals"
            record = self._find(collection, local_id, account)
            if record:
                record["sync_status"], record["sync_error"] = "failed", error[:500]
            self._touch()

    def _mark_synced(self, user_id: str, operation: dict[str, Any], response: dict[str, Any]) -> None:
        with self._lock:
            account = self._account(user_id)
            kind = operation.get("kind")
            collection = "workouts" if kind == "workout" else "meals"
            record = self._find(collection, operation.get("local_id"), account)
            if record:
                if kind == "workout":
                    record.update(response)
                    if response.get("workout_log_id"):
                        record["server_id"] = response["workout_log_id"]
                        record["id"] = response["workout_log_id"]
                else:
                    remote = response.get("log") if isinstance(response.get("log"), dict) else response
                    record.update(remote)
                    if remote.get("id"):
                        record["server_id"] = remote["id"]
                        record["id"] = remote["id"]
                record["sync_status"], record["sync_error"] = "synced", None
            account["queue"] = [x for x in account["queue"] if x.get("request_id") != operation.get("request_id")]
            self._touch()

