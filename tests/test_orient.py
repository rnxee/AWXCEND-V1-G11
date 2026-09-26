"""Rotate video: frames from a phone standing the 'wrong' way are turned upright before tracking."""
import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("cv2")
from pose.camera import orient  # noqa: E402


def frame_with_marker():
    f = np.zeros((480, 640, 3), np.uint8)  # landscape frame, marker in the top-left corner
    f[0:10, 0:10] = 255
    return f


def test_no_rotation_leaves_the_frame_alone():
    f = frame_with_marker()
    assert orient(f, 0) is f


@pytest.mark.parametrize("degrees,shape,corner", [
    (90, (640, 480, 3), (0, 479)),     # turned right: top-left ends up top-right
    (180, (480, 640, 3), (479, 639)),  # upside down: top-left ends up bottom-right
    (270, (640, 480, 3), (639, 0)),    # turned left: top-left ends up bottom-left
])
def test_rotation_turns_the_frame(degrees, shape, corner):
    out = orient(frame_with_marker(), degrees)
    assert out.shape == shape
    assert out[corner][0] == 255
