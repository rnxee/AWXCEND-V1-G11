"""One character per frame, recomputed with the counter's own measurement (not the sticky feedback):

    .  nobody detected         v  the needed joints aren't visible enough
    p  form check failed (e.g. push-up body not level)
    _  signal below 80°        0-9  signal 80-89° ... 170°+
    [Rn]  rep n counted here

    py tools/session_timeline.py "<session.csv>" [exercise]
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))
from pose.counters import EXERCISES, RepCounter  # noqa: E402
from replay_session import load  # noqa: E402


def timeline(path: pathlib.Path, exercise: str | None = None) -> str:
    exercise = exercise or path.stem.rsplit("-", 2)[0]
    measure, counter, out = EXERCISES[exercise].measure, RepCounter(exercise), []
    for t, lms, _ in load(path):
        before = counter.reps
        counter.update(lms, t)
        if lms is None:
            ch = "."
        elif (reading := measure(lms)) is None:
            ch = "v"
        elif reading[1]:
            ch = "p"
        else:
            ch = "_" if reading[0] < 80 else str(min(9, int((reading[0] - 80) // 10)))
        out.append((f"[R{counter.reps}]" if counter.reps != before else "") + ch)
    return "".join(out)


if __name__ == "__main__":
    s = timeline(pathlib.Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else None)
    for i in range(0, len(s), 100):
        print(s[i:i + 100])
