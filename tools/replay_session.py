"""Replay a saved camera session through the rep counter and show every rep and state change.

    py tools/replay_session.py "%USERPROFILE%\\AWXCEND sessions\\squat-20260926-190000.csv"

Use it to see exactly where a miscount happened, and to check a counter change against real
movement before shipping it.
"""
import csv
import pathlib
import sys
from types import SimpleNamespace

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))
from pose.camera import KEY_JOINTS  # noqa: E402
from pose.counters import RepCounter  # noqa: E402


def load(path: pathlib.Path):
    """Yield (t, landmarks or None, recorded reps) per frame."""
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get(f"x{KEY_JOINTS[0]}"):
                lms = [SimpleNamespace(x=0.0, y=0.0, visibility=0.0) for _ in range(33)]
                for i in KEY_JOINTS:
                    lms[i] = SimpleNamespace(x=float(row[f"x{i}"]), y=float(row[f"y{i}"]), visibility=float(row[f"v{i}"]))
            else:
                lms = None
            yield float(row["t"]), lms, int(row["reps"])


def replay(path: pathlib.Path, exercise: str | None = None, verbose: bool = True) -> int:
    exercise = exercise or path.stem.rsplit("-", 2)[0]
    counter, last_phase, frames = RepCounter(exercise), None, 0
    for t, lms, _ in load(path):
        frames += 1
        before = counter.reps
        counter.update(lms, t)
        if verbose and (counter.phase != last_phase or counter.reps != before):
            sig = "  -  " if counter.signal is None else f"{counter.signal:5.1f}"
            mark = f"  <== REP {counter.reps}" if counter.reps != before else ""
            print(f"{t:7.2f}s  signal {sig}  {str(last_phase):>6} -> {str(counter.phase):<6}{mark}")
        last_phase = counter.phase
    if verbose and frames:
        print(f"\n{frames} frames, {frames / max(t, 1e-6):.1f} fps, {counter.reps} reps")
    return counter.reps


if __name__ == "__main__":
    replay(pathlib.Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else None)
