"""A saved session replays to exactly what the live counter counted (so fixes can be checked on real data)."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
pytest.importorskip("cv2")  # the recorder lives in the desktop-only camera module

import pose.camera as camera  # noqa: E402
from replay_session import replay  # noqa: E402
from test_counters import squat_pose  # noqa: E402


SESSIONS = Path(__file__).parent / "sessions"


@pytest.mark.parametrize("name,exercise,real_reps", [
    ("pushup-10reps.csv", "pushup", 10),  # phone camera, 2026-09-26: counted 7 before the count line
    ("squat-8reps.csv", "squat", 8),
    ("pushup-640p-10reps.csv", "pushup", 10),  # phone at 640x480: counted 11 (reaching for the phone after)
    ("lunge-10reps.csv", "lunge", 10),  # counted 9: the far-leg lunges read shallower (96-122 deg)
    ("lunge-flowing-10reps.csv", "lunge", 10),  # counted 12: steps between lunges barely moved the hips
    ("lunge-hidden-leg-10reps.csv", "lunge", 10),  # counted 8: far leg hidden when standing disarmed it
    ("bicep_curl-sideways-10reps.csv", "bicep_curl", 10),  # video came in sideways: counted 0
])
def test_real_recorded_sets_count_what_was_actually_done(name, exercise, real_reps):
    assert replay(SESSIONS / name, exercise, verbose=False) == real_reps


def test_real_pushup_set_ignores_the_setup_and_splits_fast_reps():
    from pose.counters import RepCounter
    from replay_session import load
    c, rep_times = RepCounter("pushup"), []
    for t, lms, _ in load(SESSIONS / "pushup-10reps.csv"):
        before = c.reps
        c.update(lms, t)
        if c.reps != before:
            rep_times.append(t)
    assert len(rep_times) == 10
    assert rep_times[0] > 19  # lying down at 3 s and pushing up into a plank at 15 s is setup, not a rep
    assert any(b - a < 1.2 for a, b in zip(rep_times, rep_times[1:], strict=False))  # the quick pair near 29 s counts twice


def test_saved_session_replays_to_the_same_count(tmp_path, monkeypatch):
    monkeypatch.setattr(camera, "SESSIONS_DIR", tmp_path)
    s = camera.CameraSession("squat", on_frame=None, on_error=None)
    angles = [175, 150, 120, 90, 80, 90, 120, 150, 175] * 3
    poses = [squat_pose(175, 175)] * 7 + [squat_pose(a, a) for a in angles]  # a steady start, then 3 reps
    poses.insert(12, None)  # a frame with nobody detected is recorded too
    t = 0.0
    for p in poses:
        s.counter.update(p, t)
        s._record(t, p)
        t += 0.1
    s._save()
    assert s.counter.reps == 3
    assert s.trace_path and s.trace_path.parent == tmp_path and s.trace_path.name.startswith("squat-")
    assert replay(s.trace_path, verbose=False) == 3
