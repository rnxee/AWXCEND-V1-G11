"""Camera source parsing: webcam numbers and phone stream addresses."""
import pytest

from pose.source import parse_source


@pytest.mark.parametrize("text,expected", [
    ("0", 0),
    (" 2 ", 2),
    ("192.168.1.5:8080", "http://192.168.1.5:8080/video"),        # IP Webcam: address shown in the app
    ("http://192.168.1.5:8080", "http://192.168.1.5:8080/video"),
    ("http://192.168.1.5:8080/", "http://192.168.1.5:8080/video"),
    ("http://192.168.1.5:4747/video", "http://192.168.1.5:4747/video"),  # DroidCam
    ("https://phone.local:8080/stream.mjpeg", "https://phone.local:8080/stream.mjpeg"),
    ("rtsp://192.168.1.5:8554/live", "rtsp://192.168.1.5:8554/live"),
])
def test_parse_source(text, expected):
    assert parse_source(text) == expected


@pytest.mark.parametrize("junk", ["", "   ", "phone", "http://", "ftp://192.168.1.5/video", "192.168.1.5:abc", "-1"])
def test_parse_source_rejects_junk(junk):
    with pytest.raises(ValueError):
        parse_source(junk)
