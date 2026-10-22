"""The Run / Walk screen driven end to end with a fake GPS: consent, permission, live readings, logging."""
import asyncio
import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import flet as ft
import httpx

import gps
from fakes import FakeApp, button, walk
from views import run

LAT, LON = 14.5995, 120.9842
M_PER_DEG = 111_195.0


class Perm:
    DENIED, DENIED_FOREVER, WHILE_IN_USE = "denied", "deniedForever", "whileInUse"


class FakeGeolocator:
    answer = Perm.WHILE_IN_USE
    opened = False

    def __init__(self, configuration=None, on_position_change=None):
        self.on_position_change = on_position_change

    async def is_location_service_enabled(self):
        return True

    async def request_permission(self):
        return FakeGeolocator.answer

    async def open_app_settings(self):
        FakeGeolocator.opened = True


class FakeWakelock:
    async def enable(self):
        pass


def fake_plugin(monkeypatch):
    fg = SimpleNamespace(Geolocator=FakeGeolocator, GeolocatorPermissionStatus=Perm,
                         GeolocatorConfiguration=lambda **kw: kw, GeolocatorAndroidConfiguration=lambda **kw: kw,
                         GeolocatorPositionAccuracy=SimpleNamespace(BEST="best"))
    monkeypatch.setattr(run, "fg", fg)
    monkeypatch.setattr(run.ft, "Wakelock", FakeWakelock)


def screen(handler, platform=ft.PagePlatform.WINDOWS):
    app = FakeApp(handler, profile={"username": "ash"})
    app.page.services, app.page.platform, app.page.web = [], platform, False
    ran = []

    def run_task(coro_fn, *args):
        if coro_fn.__name__ == "tick":  # the 1 s timer loop: not needed here
            return
        ran.append(asyncio.run(coro_fn(*args)))
    app.page.run_task = run_task
    return app, run.view(app)


def reading(metres_north: float, seconds: float, accuracy: float = 5.0):
    t = datetime(2026, 10, 22, 8, 0, tzinfo=timezone.utc) + timedelta(seconds=seconds)
    pos = SimpleNamespace(latitude=LAT + metres_north / M_PER_DEG, longitude=LON, accuracy=accuracy, timestamp=t)
    return SimpleNamespace(position=pos)


def server(logged):
    def handler(req):
        if req.url.path.endswith("/privacy") and req.method == "GET":
            return httpx.Response(200, json={"success": True, "notices": {}, "latest": {}})
        if req.url.path.endswith("/log-workout"):
            logged.append(json.loads(req.content))
            return httpx.Response(200, json={"success": True, "xp_earned": 55})
        return httpx.Response(200, json={"profile": {}})
    return handler


def stream(app):
    return next(s for s in app.page.services if getattr(s, "on_position_change", None))


def test_helpers():
    assert run.clock(75) == "1:15" and run.clock(3725) == "1:02:05"
    assert run.pace(1000, 330) == "5:30/km" and run.pace(10, 5) == "–"


def test_a_walk_is_measured_and_logged_with_distance_and_time(monkeypatch):
    fake_plugin(monkeypatch)
    logged = []
    app, ctl = screen(server(logged))
    button(ctl, "Start").on_click(None)
    on = stream(app).on_position_change
    for i in range(0, 21):                     # 200 m north at 1.25 m/s
        on(reading(i * 10, i * 8.0))
    on(reading(5000, 170))                     # a GPS jump: ignored
    on(reading(200, 175, accuracy=90.0))       # a weak reading: ignored
    button(ctl, "Finish").on_click(None)
    dialog = app.dialogs[-1]
    assert "0.20 km" in dialog.content.value
    on(reading(400, 200))                      # still arriving after Finish: not counted
    button(dialog, "Keep going").on_click(None)
    button(ctl, "Finish").on_click(None)
    dialog = app.dialogs[-1]
    assert "0.20 km" in dialog.content.value   # not 0.40
    button(dialog, "Log it").on_click(None)
    assert len(logged) == 1 and logged[0]["exercise"] == "walking" and logged[0]["workout_source"] == "manual"
    assert abs(logged[0]["distance_m"] - 200) < 1 and logged[0]["duration_seconds"] >= 1


def test_a_run_under_100_m_is_not_logged(monkeypatch):
    fake_plugin(monkeypatch)
    logged = []
    app, ctl = screen(server(logged))
    button(ctl, "Start").on_click(None)
    on = stream(app).on_position_change
    for i in range(4):
        on(reading(i * 10, i * 8.0))
    button(ctl, "Finish").on_click(None)
    assert "at least 100 m" in app.dialogs[-1].content.value
    assert [c.content for c in walk(app.dialogs[-1]) if isinstance(c, (ft.FilledButton, ft.TextButton))] \
        == ["Discard", "Keep going"]            # no "Log it"
    assert logged == []


def test_without_location_permission_nothing_starts(monkeypatch):
    fake_plugin(monkeypatch)
    FakeGeolocator.answer = Perm.DENIED_FOREVER
    try:
        app, ctl = screen(server([]))
        button(ctl, "Start").on_click(None)
        assert app.toasts == ["Location permission is needed to measure distance."]
        assert app.page.services == [] and FakeGeolocator.opened      # tidied up, sent to settings
    finally:
        FakeGeolocator.answer = Perm.WHILE_IN_USE


def test_leaving_the_screen_stops_the_gps(monkeypatch):
    fake_plugin(monkeypatch)
    app, ctl = screen(server([]))
    button(ctl, "Start").on_click(None)
    assert app.page.services
    app.cleanups.pop()()                       # what App.leave() does when you switch screen
    assert app.page.services == []


def test_first_run_asks_for_the_gps_notice_and_remembers(monkeypatch):
    fake_plugin(monkeypatch)
    posted = []

    def handler(req):
        if req.url.path.endswith("/privacy") and req.method == "GET":
            return httpx.Response(200, json={"success": True, "latest": {},
                                             "notices": {"gps": {"version": "2026-10-22.v1", "title": "Before your first run",
                                                                 "body": "Only distance and time are saved."}}})
        if req.url.path.endswith("/privacy"):
            posted.append(json.loads(req.content))
        return httpx.Response(200, json={"success": True})
    app, ctl = screen(handler)
    button(ctl, "Start").on_click(None)
    assert app.page.services == []             # nothing starts before the answer
    button(app.dialogs[-1], "I agree").on_click(None)
    assert posted == [{"action": "acknowledge", "consent_type": "gps", "notice_version": "2026-10-22.v1"}]
    assert app.page.services                   # and now it does


def test_the_screen_says_so_when_the_plugin_is_missing(monkeypatch):
    monkeypatch.setattr(run, "fg", None)
    app = FakeApp(lambda r: httpx.Response(200, json={}))
    app.page.web = False
    ctl = run.view(app)
    assert any("isn't available" in (getattr(c, "value", "") or "") for c in walk(ctl))


def test_starting_twice_opens_one_gps_stream_and_a_declined_notice_unblocks_start(monkeypatch):
    fake_plugin(monkeypatch)
    app, ctl = screen(server([]))
    start = button(ctl, "Start")
    start.on_click(None)
    start.on_click(None)                       # a second tap on the same button
    assert len([s for s in app.page.services if getattr(s, "on_position_change", None)]) == 1

    def handler(req):                          # the notice is shown and declined
        if req.url.path.endswith("/privacy"):
            return httpx.Response(200, json={"success": True, "latest": {}, "notices": {
                "gps": {"version": "v1", "title": "Before your first run", "body": "x"}}})
        return httpx.Response(200, json={})
    app, ctl = screen(handler)
    button(ctl, "Start").on_click(None)
    button(app.dialogs[-1], "Not now").on_click(None)
    assert app.page.services == []
    button(ctl, "Start").on_click(None)        # Start is available again
    assert app.dialogs                         # and asks again
