"""A phone stream must never back up: a slow PC processes the NEWEST frame, not a growing queue.

Regression for 2026-09-26: 10 push-ups counted 3-5 because frames queued behind slow processing,
the app fell seconds behind and then dropped whole chunks of video (whole reps).
"""
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

cv2 = pytest.importorskip("cv2")
np = pytest.importorskip("numpy")
from pose.camera import CameraSession  # noqa: E402

FPS = 30


def _stream_server(state, run):
    class Stream(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            i, t0 = 0, time.perf_counter()
            while run.is_set():
                img = np.zeros((480, 640, 3), np.uint8)
                for bit in range(12):  # the frame number, as 12 black/white squares
                    img[0:40, bit * 40:(bit + 1) * 40] = 255 if (i >> bit) & 1 else 0
                ok, jpg = cv2.imencode(".jpg", img)
                try:
                    self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % len(jpg))
                    self.wfile.write(jpg.tobytes() + b"\r\n")
                except OSError:
                    return
                state["sent"] = i
                i += 1
                time.sleep(max(0.0, t0 + i / FPS - time.perf_counter()))

        def log_message(self, *a):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Stream)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def _frame_number(jpg: bytes) -> int:
    img = cv2.flip(cv2.imdecode(np.frombuffer(jpg, np.uint8), cv2.IMREAD_GRAYSCALE), 1)  # undo the mirror
    return sum(1 << b for b in range(12) if img[20, b * 40 + 20] > 127)


def test_slow_processing_stays_on_the_newest_frame():
    state, run, lags = {"sent": 0}, threading.Event(), []
    run.set()
    server = _stream_server(state, run)

    def on_frame(jpg, counter, left):
        lags.append((time.perf_counter(), state["sent"] - _frame_number(jpg)))
        time.sleep(0.12)  # a busy PC: ~7 frames/s from a 30 frames/s phone

    session = CameraSession("pushup", on_frame, lambda msg: None,
                            source=f"http://127.0.0.1:{server.server_address[1]}/video", countdown=0)
    start = time.perf_counter()
    session.start()
    time.sleep(6)
    arriving_fps, size = session.reader.fps, session.reader.size
    session.stop()
    run.clear()
    server.shutdown()
    late = [lag for t, lag in lags if t - start > 3.5]
    assert len(late) >= 5, "the stream never produced frames"
    # a few frames of slack for detection time on a busy machine; the old queue was 29+ frames and growing
    assert max(late) <= 10, f"fell behind the live stream by up to {max(late)} frames"
    # the on-screen readout reports what the camera really sends, not what the PC manages to process
    assert size == (640, 480)
    assert 22 <= arriving_fps <= 36, arriving_fps
