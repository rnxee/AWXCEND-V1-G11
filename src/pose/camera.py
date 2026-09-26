"""Desktop camera loop: webcam -> MediaPipe pose -> rep counter -> annotated JPEG for the UI.

Runs in its own thread; the UI gets (jpeg_bytes, counter, countdown_left) for every frame.
"""
import csv
import os
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Callable

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision

from pose.counters import RepCounter

MODEL = os.path.join(os.path.dirname(__file__), "..", "assets", "pose_landmarker_lite.task")
BONES = [(11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24),
         (23, 25), (25, 27), (24, 26), (26, 28)]
CYAN, VIOLET = (238, 211, 34), (250, 139, 167)  # BGR


# Every set is saved as numbers (joint positions + counter state, never video) so miscounts can be
# replayed and fixed against real movement: py tools/replay_session.py "<file>".
SESSIONS_DIR = Path.home() / "AWXCEND sessions"
KEY_JOINTS = (11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
MAX_WIDTH = 720      # phone streams are often 1080p+: shrink before pose detection
FEED_TIMEOUT_S = 5   # no frame for this long = the phone/webcam went away


ROTATIONS = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180, 270: cv2.ROTATE_90_COUNTERCLOCKWISE}


def orient(frame, degrees: int):
    """Turn a frame upright (a phone standing the other way sends sideways video). Clockwise degrees."""
    return cv2.rotate(frame, ROTATIONS[degrees]) if degrees in ROTATIONS else frame


class LatestFrame:
    """Reads the camera/stream nonstop on its own thread and keeps ONLY the newest frame.

    Without this, a phone stream that sends frames faster than pose detection can use them queues
    up: the app falls further and further behind, then whole chunks (whole reps) get dropped.
    """

    def __init__(self, cap, stop: threading.Event):
        self.cap, self.stop = cap, stop
        self.cond = threading.Condition()
        self.frame, self.t, self.seq = None, 0.0, 0
        self.last_ok = time.perf_counter()
        self.arrivals: deque[float] = deque(maxlen=45)  # recent arrival times, for the live fps readout
        self.size = (0, 0)  # the source's own resolution, before any downscaling

    def run(self) -> None:
        try:
            while not self.stop.is_set():
                ok, frame = self.cap.read()
                now = time.perf_counter()
                with self.cond:
                    if ok:
                        self.frame, self.t, self.seq, self.last_ok = frame, now, self.seq + 1, now
                        self.arrivals.append(now)
                        self.size = (frame.shape[1], frame.shape[0])
                    self.cond.notify_all()
                if not ok:
                    time.sleep(0.02)
        finally:
            self.cap.release()  # released here: never while this thread is inside read()

    @property
    def fps(self) -> float:
        """Frames per second actually arriving from the camera/phone (recent average)."""
        a = self.arrivals
        return (len(a) - 1) / (a[-1] - a[0]) if len(a) > 1 and a[-1] > a[0] else 0.0

    def newer_than(self, seq: int, timeout: float = 0.5):
        """(seq, frame, arrival time) of the newest frame, waiting briefly for one newer than `seq`."""
        with self.cond:
            self.cond.wait_for(lambda: self.seq != seq or self.stop.is_set(), timeout)
            return self.seq, self.frame, self.t


class CameraSession:
    def __init__(self, exercise: str, on_frame: Callable, on_error: Callable[[str], None],
                 source: int | str = 0, countdown: int = 3, rotate: int = 0):
        self.counter = RepCounter(exercise)
        self.exercise = exercise
        self.on_frame, self.on_error, self.countdown, self.source = on_frame, on_error, countdown, source
        self._stop = threading.Event()
        self.rotate = rotate  # read every frame, so the picker can fix a sideways video mid-set
        self.rows: list[list] = []
        self.trace_path: Path | None = None
        self.reader: LatestFrame | None = None  # live stream stats for the UI

    def start(self) -> None:
        threading.Thread(target=self._run, daemon=True).start()

    def stop(self) -> None:
        self._stop.set()

    def _open(self):
        if isinstance(self.source, str):  # phone stream over Wi-Fi
            timeout_ms = FEED_TIMEOUT_S * 1000  # fail fast on a wrong address instead of hanging
            cap = cv2.VideoCapture(self.source, cv2.CAP_FFMPEG,
                                   [cv2.CAP_PROP_OPEN_TIMEOUT_MSEC, timeout_ms, cv2.CAP_PROP_READ_TIMEOUT_MSEC, timeout_ms])
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # always the newest frame, not a backlog
            return cap
        cap = cv2.VideoCapture(self.source, cv2.CAP_DSHOW) if os.name == "nt" else cv2.VideoCapture(self.source)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        return cap

    def _run(self) -> None:
        cap = self._open()
        if not cap.isOpened():
            self.on_error(f"Couldn't connect to the phone at {self.source}. Check the camera app is streaming "
                          "and both devices are on the same Wi-Fi." if isinstance(self.source, str) else
                          f"Webcam {self.source + 1} not found. Pick another camera or close apps using it.")
            cap.release()
            return
        reader = self.reader = LatestFrame(cap, self._stop)
        threading.Thread(target=reader.run, daemon=True).start()
        opts = vision.PoseLandmarkerOptions(base_options=BaseOptions(model_asset_path=MODEL),
                                            running_mode=vision.RunningMode.VIDEO)
        try:
            with vision.PoseLandmarker.create_from_options(opts) as landmarker:
                t0, seq, last_ms = time.perf_counter(), 0, -1
                while not self._stop.is_set():
                    new_seq, frame, t_frame = reader.newer_than(seq)
                    if new_seq == seq:  # nothing new arrived
                        if time.perf_counter() - reader.last_ok > FEED_TIMEOUT_S:
                            self.on_error("Lost the camera feed. Check the phone app is still streaming.")
                            return
                        continue
                    skipped, seq = new_seq - seq - 1, new_seq
                    work_start = time.perf_counter()
                    frame = orient(frame, self.rotate)
                    if frame.shape[1] > MAX_WIDTH:
                        scale = MAX_WIDTH / frame.shape[1]
                        frame = cv2.resize(frame, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
                    elapsed = t_frame - t0  # when the frame ARRIVED, so rep timing stays true
                    last_ms = max(last_ms + 1, int(elapsed * 1000))  # MediaPipe needs increasing timestamps
                    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), last_ms)
                    lms = result.pose_landmarks[0] if result.pose_landmarks else None
                    if lms:
                        _draw(frame, lms)
                    left = self.countdown - elapsed
                    if left <= 0:
                        self.counter.update(lms, elapsed)
                    frame = cv2.flip(frame, 1)  # mirror, like looking in a mirror
                    if left > 0:
                        _countdown(frame, int(left) + 1)
                    ok, jpg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
                    if ok and not self._stop.is_set():
                        self.on_frame(jpg.tobytes(), self.counter, max(left, 0))
                    if left <= 0:
                        self._record(elapsed, lms, (time.perf_counter() - work_start) * 1000, skipped)
        except Exception as e:  # model load / camera driver failures: tell the user, don't crash the app
            if not self._stop.is_set():  # after Finish, a half-processed frame's error doesn't matter
                self.on_error(f"Camera tracking stopped: {e}")
        finally:
            self._stop.set()  # also ends the reader thread, which releases the camera
            self._save()

    def _record(self, t: float, lms, work_ms: float = 0.0, skipped: int = 0) -> None:
        """work_ms: time spent on this frame (detect + draw + UI); skipped: newer frames that arrived meanwhile."""
        c = self.counter
        joints = [round(v, 4) for i in KEY_JOINTS for v in (lms[i].x, lms[i].y, lms[i].visibility)] if lms else []
        self.rows.append([round(t, 3), c.reps, c.phase or "", "" if c.signal is None else round(c.signal, 1),
                          c.feedback, round(work_ms), skipped, *joints])

    def _save(self) -> None:
        if not self.rows:
            return
        try:
            SESSIONS_DIR.mkdir(exist_ok=True)
            path = SESSIONS_DIR / f"{self.exercise}-{datetime.now():%Y%m%d-%H%M%S}.csv"
            tmp = path.with_suffix(".partial")  # written in full first: closing the app mid-save
            with tmp.open("w", newline="", encoding="utf-8") as f:  # can't leave an empty .csv
                w = csv.writer(f)
                w.writerow(["t", "reps", "phase", "signal", "feedback", "work_ms", "skipped"]
                           + [f"{k}{i}" for i in KEY_JOINTS for k in ("x", "y", "v")])
                w.writerows(self.rows)
            os.replace(tmp, path)
            self.trace_path = path
        except OSError:
            pass  # a diagnostics file must never break the workout


def _draw(frame, lms) -> None:
    h, w = frame.shape[:2]
    pts = {i: (int(lms[i].x * w), int(lms[i].y * h)) for i in range(11, 29) if lms[i].visibility > 0.5}
    for a, b in BONES:
        if a in pts and b in pts:
            cv2.line(frame, pts[a], pts[b], CYAN, 3, cv2.LINE_AA)
    for p in pts.values():
        cv2.circle(frame, p, 5, VIOLET, -1, cv2.LINE_AA)


def _countdown(frame, n: int) -> None:
    h, w = frame.shape[:2]
    text = str(n)
    (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_DUPLEX, 5, 8)
    cv2.putText(frame, text, ((w - tw) // 2, (h + th) // 2), cv2.FONT_HERSHEY_DUPLEX, 5, (255, 255, 255), 8, cv2.LINE_AA)
