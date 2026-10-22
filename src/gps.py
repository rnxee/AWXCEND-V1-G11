"""Distance from GPS readings, for runs and walks. Pure Python (no Flet, no clock) so it can be tested
with made-up routes; views/run.py feeds it the live readings.

A phone's GPS drifts a few metres even when you stand still and now and then jumps. Counting every
reading would hand out free distance, so a reading only counts when:
  * it is accurate enough (accuracy at most MAX_ACCURACY_M),
  * it is in time order,
  * getting there did not need a speed no walker or runner reaches (MAX_SPEED_MS): that is a GPS jump,
  * it is at least MIN_STEP_M from the last counted point: standing still adds nothing.
Nothing here stops someone faking their location on their own phone; the server also caps one log
(200 km) and these checks keep honest tracking honest.
"""
import math

MAX_ACCURACY_M = 30.0   # a phone outdoors reports 3-10 m; a PC (Wi-Fi location) reports 100+ m and can't count
MAX_SPEED_MS = 10.0     # 36 km/h: faster than a sprint held over a step, so a jump rather than a runner
MIN_STEP_M = 3.0        # about the drift of a phone lying still
EARTH_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres between two points given in degrees."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_M * math.asin(math.sqrt(a))


class Track:
    def __init__(self):
        self.distance_m = 0.0
        self.last: tuple[float, float, float] | None = None  # lat, lon, seconds of the last counted point

    def break_here(self) -> None:
        """After a pause: the next reading starts a new stretch instead of counting the walk home in a car."""
        self.last = None

    def add(self, lat: float, lon: float, accuracy: float, t: float) -> str:
        """One GPS reading. Returns 'counted', 'start' (first point of a stretch) or why it was skipped:
        'weak', 'late', 'jump' or 'still'."""
        if accuracy is None or accuracy <= 0 or accuracy > MAX_ACCURACY_M:
            return "weak"  # 0 means "not reported" in the plugin: not trusted either
        if self.last is None:
            self.last = (lat, lon, t)
            return "start"
        plat, plon, pt = self.last
        if t <= pt:
            return "late"
        step = haversine_m(plat, plon, lat, lon)
        if step / (t - pt) > MAX_SPEED_MS:
            return "jump"
        if step < max(MIN_STEP_M, accuracy / 2):
            return "still"
        self.distance_m += step
        self.last = (lat, lon, t)
        return "counted"
