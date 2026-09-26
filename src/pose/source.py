"""What the camera picker's text means: a webcam number, or a phone's video stream address."""
from urllib.parse import urlsplit


def parse_source(text: str) -> int | str:
    """'1' -> webcam 1. '192.168.1.5:8080' or 'http://192.168.1.5:8080' -> that phone's IP Webcam
    stream (…/video). Full stream URLs (DroidCam, RTSP) pass through unchanged."""
    text = text.strip()
    if text.isdigit():
        return int(text)
    url = text if "://" in text else f"http://{text}"
    parts = urlsplit(url)
    try:
        port_ok = parts.port is None or parts.port > 0
    except ValueError:  # "192.168.1.5:abc"
        port_ok = False
    if parts.scheme not in ("http", "https", "rtsp") or not parts.hostname or not port_ok:
        raise ValueError("Enter a webcam number or the phone address, like 192.168.1.5:8080")
    if "." not in parts.hostname and ":" not in parts.netloc:  # a bare word like "phone"
        raise ValueError("Enter a webcam number or the phone address, like 192.168.1.5:8080")
    if parts.scheme != "rtsp" and parts.path in ("", "/"):
        return f"{parts.scheme}://{parts.netloc}/video"  # IP Webcam's stream path
    return url
