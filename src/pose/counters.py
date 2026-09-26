"""Angle-threshold rep counters. Pure Python: landmarks in, reps and feedback out.

A rep is: start at the top (joint open) -> reach the bottom -> return to the top.
The gap between the top and bottom thresholds is the hysteresis that stops jitter from
double counting. Frames with a form fault are skipped, never counted and never reset.
ponytail: no extra smoothing - MediaPipe's VIDEO mode already smooths landmarks and the
threshold gap absorbs the rest. Add an EMA on the signal if real webcams prove noisier.
"""
import math
from dataclasses import dataclass
from typing import Callable

VISIBLE = 0.5       # MediaPipe landmark visibility needed to trust a joint
MIN_REP_S = 0.3     # faster than this is a bounce or a glitch, not a rep
READY_S = 0.5      # hold the start position this long before counting begins (setup moves aren't reps)
DISARM_S = 1.0     # out of position this long (stood up, walked off) = the set is over; re-arm with READY_S
MAX_REP_S = 6.0     # longer than this is getting into position or resting, not a rep (real reps: 0.8-2.5 s)
PARTIAL_DROP = 25   # degrees below the top that count as "tried, but not deep enough"

L_SH, R_SH, L_EL, R_EL, L_WR, R_WR = 11, 12, 13, 14, 15, 16
L_HIP, R_HIP, L_KN, R_KN, L_AN, R_AN = 23, 24, 25, 26, 27, 28
LEFT = {"sh": L_SH, "el": L_EL, "wr": L_WR, "hip": L_HIP, "kn": L_KN, "an": L_AN}
RIGHT = {"sh": R_SH, "el": R_EL, "wr": R_WR, "hip": R_HIP, "kn": R_KN, "an": R_AN}

# (signal, fault) - fault is a message when this frame's form doesn't qualify
Reading = tuple[float, str | None]


def angle(a, b, c) -> float:
    """Inner angle at b, in degrees (0-180)."""
    deg = abs(math.degrees(math.atan2(a[1] - b[1], a[0] - b[0]) - math.atan2(c[1] - b[1], c[0] - b[0])))
    return 360 - deg if deg > 180 else deg


def _pt(lms, i):
    return (lms[i].x, lms[i].y)


def _visible(lms, idx) -> bool:
    return all(lms[i].visibility >= VISIBLE for i in idx)


def _joint(lms, side, a, b, c) -> float:
    return angle(_pt(lms, side[a]), _pt(lms, side[b]), _pt(lms, side[c]))


def _best_side(lms, keys):
    """The side whose needed joints are more visible (side-view exercises), or None."""
    score = lambda side: sum(lms[side[k]].visibility for k in keys)
    side = max((LEFT, RIGHT), key=score)
    return side if _visible(lms, [side[k] for k in keys]) else None


def _tilt_from_vertical(a, b) -> float:
    return math.degrees(math.atan2(abs(b[0] - a[0]), abs(b[1] - a[1])))


def _knees(lms):
    if not _visible(lms, [s[k] for s in (LEFT, RIGHT) for k in ("hip", "kn", "an")]):
        return None
    return _joint(lms, LEFT, "hip", "kn", "an"), _joint(lms, RIGHT, "hip", "kn", "an")


LUNGE_TOP = 160


def _lunge(lms) -> Reading | None:
    legs = [side for side in (LEFT, RIGHT) if _visible(lms, [side[k] for k in ("hip", "kn", "an")])]
    if not legs:
        return None
    angles = [_joint(lms, side, "hip", "kn", "an") for side in legs]
    if len(legs) == 2:
        return max(angles), None  # the straighter knee must bend too: a one-leg kick isn't a lunge
    # Standing side-on with the legs together, the far leg hides behind the near one. One straight
    # visible leg is enough to know you're standing; a bent one alone can't tell us anything.
    return (angles[0], None) if angles[0] >= LUNGE_TOP else None


def _mid(lms, a: int, b: int):
    return (lms[a].x + lms[b].x) / 2, (lms[a].y + lms[b].y) / 2


class StandingReference:
    """The user's own standing posture, learned while they stand: which way is 'up' along their body
    (hips -> shoulders), where the hips sit along it, and their leg length. Measuring against the body
    instead of the picture means a sideways phone video works too."""

    RATE = 0.2    # how fast 'up' and leg length follow small changes in stance
    DECAY = 0.02  # how slowly the standing hip height is allowed to come down

    def __init__(self):
        self.up = self.s0 = self.leg = None

    def learn(self, lms) -> None:
        if not _visible(lms, (L_SH, R_SH, L_HIP, R_HIP)):
            return
        ankle = max((L_AN, R_AN), key=lambda i: lms[i].visibility)
        if lms[ankle].visibility < VISIBLE:
            return
        sh, hip = _mid(lms, L_SH, R_SH), _mid(lms, L_HIP, R_HIP)
        n = math.hypot(sh[0] - hip[0], sh[1] - hip[1])
        if n < 1e-6:
            return
        up = ((sh[0] - hip[0]) / n, (sh[1] - hip[1]) / n)
        leg = math.dist(hip, (lms[ankle].x, lms[ankle].y))
        if self.up is None:
            self.up, self.leg = up, leg
            self.s0 = hip[0] * up[0] + hip[1] * up[1]
            return
        r = self.RATE
        ux, uy = (1 - r) * self.up[0] + r * up[0], (1 - r) * self.up[1] + r * up[1]
        m = math.hypot(ux, uy)
        self.up = (ux / m, uy / m)
        self.leg = (1 - r) * self.leg + r * leg
        # Standing hip height snaps UP instantly and only drifts down slowly, so a half-bent moment
        # between reps (users flow from lunge to lunge) can't drag the reference down.
        s = hip[0] * self.up[0] + hip[1] * self.up[1]
        self.s0 = s if s > self.s0 else self.s0 - self.DECAY * (self.s0 - s)

    def hip_drop(self, lms) -> float | None:
        """How far the hips are below standing height, in leg lengths (0 = standing)."""
        if self.up is None or not _visible(lms, (L_HIP, R_HIP)) or self.leg <= 0:
            return None
        hip = _mid(lms, L_HIP, R_HIP)
        return (self.s0 - (hip[0] * self.up[0] + hip[1] * self.up[1])) / self.leg


def _squat(lms) -> Reading | None:
    knees = _knees(lms)
    # The straighter knee drives the rep, so both knees must bend: a knee raise can't count.
    return None if knees is None else (max(knees), None)


def _pushup(lms) -> Reading | None:
    side = _best_side(lms, ("sh", "el", "wr", "hip"))
    if side is None:
        return None
    flat = _tilt_from_vertical(_pt(lms, side["sh"]), _pt(lms, side["hip"])) > 45
    return _joint(lms, side, "sh", "el", "wr"), None if flat else "Get into a plank - body level with the floor"


def _curl(lms) -> Reading | None:
    side = _best_side(lms, ("sh", "el", "wr", "hip"))
    if side is None:
        return None
    # Upper arm vs the torso (not the picture's vertical), so a sideways phone video still works.
    # Real strict curls stayed within 17-27 deg of the torso; a swing goes well past 40.
    swinging = _joint(lms, side, "el", "sh", "hip") > 40
    return _joint(lms, side, "sh", "el", "wr"), "Keep your elbow still at your side" if swinging else None


@dataclass(frozen=True)
class Exercise:
    label: str
    log_as: str          # public.exercises name used by log-workout
    tip: str             # camera setup, shown before starting
    measure: Callable[[list], Reading | None]
    top: float           # signal at or above this = start position
    bottom: float        # signal at or below this = full depth ("Good rep")
    partial: str         # said when a rep turns back before full depth
    count_at: float | None = None  # a rep counts once it gets this deep (defaults to `bottom`);
    #                               between count_at and bottom it counts with the `partial` tip
    min_rep_s: float = MIN_REP_S   # a real rep of this exercise can't be quicker than this
    min_hip_drop: float | None = None  # hips must drop this far (in leg lengths) for a rep to count


EXERCISES: dict[str, Exercise] = {
    "pushup": Exercise(
        "Push-up", "pushup",
        "Turn side-on to the camera, about 2 m away, with your whole body in frame.",
        # From real recorded sets (tests/sessions): bottoms reached 80-119 deg, and between quick reps
        # the arms only straightened to 140-150 deg - at 100/150 the counter missed 3 of 10.
        _pushup, top=140, bottom=100, count_at=120, partial="Go lower - chest toward the floor"),
    "squat": Exercise(
        "Squat", "squat",
        "Face the camera, about 2.5 m away, with your whole body in frame.",
        _squat, top=160, bottom=105, partial="Go lower - hips down to knee height"),
    "lunge": Exercise(
        "Lunge", "lunges",
        "Turn side-on to the camera with both legs in frame.",
        _lunge,
        # From real sets: lunges on the leg far from the camera read shallower (96-122 deg vs 64-73),
        # every real lunge took 1.2-2.2 s while weight-shift wobbles lasted 0.2-0.3 s, and real lunges
        # dropped the hips 24-62% of leg length while steps/wobbles dropped them 9-14% (0.10-0.20 all work).
        top=LUNGE_TOP, bottom=120, count_at=135, min_rep_s=0.8, min_hip_drop=0.15,
        partial="Go lower - back knee toward the floor"),
    "bicep_curl": Exercise(
        "Bicep Curl", "barbellbicepscurl",
        "Turn side-on so your working arm faces the camera, with your hips in frame.",
        _curl, top=150, bottom=60, partial="Curl all the way up"),
}


class RepCounter:
    def __init__(self, key: str):
        self.ex = EXERCISES[key]
        self.reps = 0
        self.signal: float | None = None
        self.feedback = self.ex.tip
        self._phase: str | None = None   # None until the start position is seen; then top/down/bottom
        self._t_top = 0.0
        self._low = math.inf
        self._fault: str | None = None
        self._ready_since: float | None = None  # start of the current steady start-position hold
        self._out_since: float | None = None    # when the user left the position (fault / not visible)
        self._ref = StandingReference() if self.ex.min_hip_drop else None
        self._drop = 0.0                         # deepest hip drop in the current rep

    def _out_of_position(self, t: float) -> None:
        """One bad frame is skipped; staying out of position ends the set (the counter disarms)."""
        self._ready_since = None
        if self._out_since is None:
            self._out_since = t
        elif self._phase is not None and t - self._out_since >= DISARM_S:
            self._phase, self._low, self._fault = None, math.inf, None

    @property
    def phase(self) -> str | None:
        return self._phase

    def update(self, lms, t: float) -> None:
        reading = self.ex.measure(lms) if lms else None  # None: no person detected
        if reading is None or reading[1]:
            self._out_of_position(t)
            if reading is None:
                self.feedback = "Step back - keep your whole body in view"
                return
            self.signal, fault = reading
            self.feedback = self._fault = fault
            return
        self._out_since = None
        self.signal, fault = reading
        ex = self.ex
        if self._ref is not None:
            if self.signal >= ex.top and self._phase in (None, "top"):
                self._ref.learn(lms)  # standing: keep the reference current
            elif self._phase in ("down", "bottom") and (d := self._ref.hip_drop(lms)) is not None:
                self._drop = max(self._drop, d)
        if self.signal >= ex.top:
            if self._phase == "bottom":
                if t - self._t_top > MAX_REP_S:
                    self.feedback = "Ready - start your reps"
                elif self._ref is not None and self._ref.up is not None and self._drop < ex.min_hip_drop:
                    self.feedback = ex.partial  # the knees bent but the body didn't go down
                elif t - self._t_top >= ex.min_rep_s:
                    self.reps += 1
                    self.feedback = "Good rep" if self._low <= ex.bottom else f"Counted - {ex.partial[0].lower()}{ex.partial[1:]}"
                else:
                    self.feedback = "Too fast - control the movement"
            elif self._phase == "down" and self._low < ex.top - PARTIAL_DROP:
                self.feedback = self._fault or ex.partial
            elif self._phase is None:
                if self._ready_since is None:
                    self._ready_since = t
                if t - self._ready_since < READY_S:
                    return  # not steady yet: arms flashing straight while setting up doesn't arm the counter
                self.feedback = "Ready - start your reps"
            self._phase, self._t_top, self._low, self._fault, self._drop = "top", t, math.inf, None, 0.0
        elif self._phase is None:
            self._ready_since = None
        else:
            self._low = min(self._low, self.signal)
            if self.signal <= (ex.bottom if ex.count_at is None else ex.count_at):
                self._phase = "bottom"
            elif self._phase == "top":
                self._phase = "down"
