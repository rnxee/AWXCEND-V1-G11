"""Client for the AWXCEND backend: Supabase Auth (REST) + Edge Functions.

Every function call carries `Authorization: Bearer <access token>`. An expired token gets
one refresh-and-retry; if the refresh fails too, the session is cleared (signed out).
"""
import re
import threading
from typing import Any, Callable
from urllib.parse import parse_qs, urlsplit

import httpx

Session = dict[str, Any]


class ApiError(Exception):
    def __init__(self, message: str, status: int = 0, code: str | None = None):
        super().__init__(message)
        self.status = status
        self.code = code


def _error_from(res: httpx.Response) -> ApiError:
    if res.status_code == 429:
        return ApiError("Too many requests - slow down and try again in a minute.", 429)
    try:
        body = res.json()
    except ValueError:
        body = {}
    if not isinstance(body, dict):
        body = {}
    code = body.get("code")
    if body.get("errors"):
        msg = ", ".join(map(str, body["errors"]))
    else:
        msg = str(body.get("error_description") or body.get("error") or body.get("msg")
                  or body.get("message") or f"Request failed ({res.status_code})")
        # log-workout style "CODE: human message"
        head, sep, rest = msg.partition(": ")
        if sep and head.isupper() and "_" in head and not code:
            code, msg = head, rest
    return ApiError(msg, res.status_code, code)


class Api:
    def __init__(self, url: str, key: str, transport: httpx.BaseTransport | None = None,
                 on_session: Callable[[Session | None], None] | None = None):
        self.url = url.rstrip("/")
        self.key = key
        self.http = httpx.Client(timeout=30, transport=transport)
        self.on_session = on_session or (lambda s: None)
        self.session: Session | None = None
        self._refresh_lock = threading.Lock()

    # ---- session -------------------------------------------------------------
    @property
    def user_id(self) -> str | None:
        return self.session["user"]["id"] if self.session else None

    def set_session(self, session: Session | None) -> None:
        self.session = session
        self.on_session(session)

    def _send(self, method: str, url: str, **kw) -> httpx.Response:
        try:
            return self.http.request(method, url, **kw)
        except httpx.HTTPError as e:
            raise ApiError("Can't reach the server. Check your connection and try again.") from e

    def _auth(self, path: str, body: dict | None = None, method: str = "POST",
              params: dict | None = None, bearer: str | None = None) -> dict:
        headers = {"apikey": self.key, "Authorization": f"Bearer {bearer or self.key}"}
        res = self._send(method, f"{self.url}/auth/v1/{path}", json=body, params=params, headers=headers)
        if res.is_error:
            raise _error_from(res)
        return res.json() if res.content else {}

    # ---- auth ----------------------------------------------------------------
    def sign_up(self, email: str, password: str) -> Session | None:
        data = self._auth("signup", {"email": email, "password": password})
        if data.get("access_token"):
            self.set_session(data)
            return data
        return None  # email confirmation is on: no session yet

    def sign_in(self, email: str, password: str) -> Session:
        data = self._auth("token", {"email": email, "password": password}, params={"grant_type": "password"})
        self.set_session(data)
        return data

    def refresh(self) -> None:
        stale = self.session
        with self._refresh_lock:
            if self.session is not stale:  # another thread already refreshed
                return
            try:
                data = self._auth("token", {"refresh_token": stale["refresh_token"]},
                                  params={"grant_type": "refresh_token"})
            except ApiError as e:
                if e.status:  # the server said no: this login is over
                    self.set_session(None)
                    raise ApiError("Your session expired. Please log in again.", 401) from e
                raise
            self.set_session(data)

    def send_recovery_code(self, email: str) -> None:
        self._auth("recover", {"email": email})

    def recover(self, email: str, pasted: str) -> None:
        """Sign in from a password-reset email, whatever the user pasted: the email's link, the
        address the browser landed on after opening it, or a code (if the project emails codes)."""
        text = pasted.strip()
        url = urlsplit(text)
        query, fragment = parse_qs(url.query), parse_qs(url.fragment)
        digits = re.sub(r"\s", "", text)
        if query.get("type") == ["recovery"] and query.get("token"):
            self.set_session(self._auth("verify", {"type": "recovery", "token_hash": query["token"][0]}))
        elif fragment.get("access_token") and fragment.get("refresh_token"):
            token = fragment["access_token"][0]
            user = self._auth("user", method="GET", bearer=token)
            self.set_session({"access_token": token, "refresh_token": fragment["refresh_token"][0], "user": user})
        elif digits.isdigit() and 6 <= len(digits) <= 10:
            self.set_session(self._auth("verify", {"type": "recovery", "email": email, "token": digits}))
        else:
            raise ApiError("Paste the whole reset link from the email (or the page address it opened).")

    def set_password(self, password: str) -> None:
        self._auth("user", {"password": password}, method="PUT", bearer=self.session["access_token"])

    def sign_out(self) -> None:
        if self.session:
            try:
                self._auth("logout", bearer=self.session["access_token"])
            except ApiError:
                pass  # signing out locally is what matters
        self.set_session(None)

    # ---- edge functions ------------------------------------------------------
    def call(self, fn: str, method: str = "GET", body: Any = None,
             params: dict | None = None, anon: bool = False) -> Any:
        for attempt in (1, 2):
            token = self.key if anon or not self.session else self.session["access_token"]
            res = self._send(method, f"{self.url}/functions/v1/{fn}", json=body, params=params,
                             headers={"Authorization": f"Bearer {token}"})
            if res.status_code == 401 and attempt == 1 and self.session and not anon:
                self.refresh()
                continue
            if res.is_error:
                raise _error_from(res)
            return res.json() if res.content else None
