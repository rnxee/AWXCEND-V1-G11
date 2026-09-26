"""API client: auth, token refresh and error mapping against a fake server (no network)."""
import json

import httpx
import pytest

from api import Api, ApiError

URL = "https://example.supabase.co"


def session(n):
    return {"access_token": f"tok{n}", "refresh_token": f"ref{n}", "user": {"id": "u1", "email": "a@example.com"}}


def make(handler, saved=None):
    saved = saved if saved is not None else []
    api = Api(URL, "pub-key", transport=httpx.MockTransport(handler), on_session=saved.append)
    return api, saved


def test_sign_in_stores_and_reports_the_session():
    def handler(req):
        assert req.url.path == "/auth/v1/token" and req.url.params["grant_type"] == "password"
        assert req.headers["apikey"] == "pub-key"
        assert json.loads(req.content) == {"email": "a@example.com", "password": "pw123456"}
        return httpx.Response(200, json=session(1))

    api, saved = make(handler)
    api.sign_in("a@example.com", "pw123456")
    assert api.user_id == "u1"
    assert saved[-1]["access_token"] == "tok1"


def test_call_sends_bearer_and_refreshes_once_on_401():
    seen = []

    def handler(req):
        if req.url.path == "/auth/v1/token":
            assert req.url.params["grant_type"] == "refresh_token"
            assert json.loads(req.content) == {"refresh_token": "ref1"}
            return httpx.Response(200, json=session(2))
        seen.append(req.headers["authorization"])
        if req.headers["authorization"] == "Bearer tok1":
            return httpx.Response(401, json={"error": "expired"})
        return httpx.Response(200, json={"success": True, "profile": {"xp": 5}})

    api, saved = make(handler)
    api.set_session(session(1))
    assert api.call("profile")["profile"]["xp"] == 5
    assert seen == ["Bearer tok1", "Bearer tok2"]
    assert saved[-1]["refresh_token"] == "ref2"


def test_failed_refresh_signs_out():
    def handler(req):
        if req.url.path == "/auth/v1/token":
            return httpx.Response(400, json={"error_description": "Invalid Refresh Token"})
        return httpx.Response(401, json={"error": "expired"})

    api, saved = make(handler)
    api.set_session(session(1))
    with pytest.raises(ApiError) as e:
        api.call("profile")
    assert e.value.status == 401
    assert api.session is None and saved[-1] is None


@pytest.mark.parametrize("status,body,code,msg", [
    (400, {"success": False, "errors": ["reps must be 1-300", "sets must be 1-20"]}, None, "reps must be 1-300, sets must be 1-20"),
    (400, {"success": False, "error": "CAMERA_NOT_VALIDATED: camera sets are not accepted"}, "CAMERA_NOT_VALIDATED", "camera sets are not accepted"),
    (400, {"success": False, "error": "Username taken", "code": "USERNAME_TAKEN"}, "USERNAME_TAKEN", "Username taken"),
    (429, {"error": "Too many requests"}, None, "slow down"),
    (400, {"msg": "Invalid login credentials"}, None, "Invalid login credentials"),
])
def test_errors_become_readable_messages(status, body, code, msg):
    api, _ = make(lambda req: httpx.Response(status, json=body))
    api.set_session(session(1))
    with pytest.raises(ApiError) as e:
        api.call("log-workout", "POST", {"exercise": "squat"})
    assert e.value.code == code
    assert msg.lower() in str(e.value).lower()


def test_network_failure_is_a_friendly_error():
    def handler(req):
        raise httpx.ConnectError("boom")

    api, _ = make(handler)
    api.set_session(session(1))
    with pytest.raises(ApiError) as e:
        api.call("profile")
    assert "connection" in str(e.value).lower()


RESET_LINK = ("https://example.supabase.co/auth/v1/verify?token=pkce_abc123&type=recovery"
              "&redirect_to=http://localhost:3000")
LANDED_URL = ("http://localhost:3000/#access_token=AT9&expires_at=1&expires_in=3600"
              "&refresh_token=RT9&token_type=bearer&type=recovery")


def test_recover_with_the_emailed_link():
    def handler(req):
        assert req.url.path == "/auth/v1/verify"
        assert json.loads(req.content) == {"type": "recovery", "token_hash": "pkce_abc123"}
        return httpx.Response(200, json=session(3))

    api, saved = make(handler)
    api.recover("a@example.com", f"  {RESET_LINK}\n")
    assert api.session["access_token"] == "tok3" and saved[-1]["access_token"] == "tok3"


def test_recover_with_the_page_you_land_on_after_opening_the_link():
    def handler(req):
        assert req.url.path == "/auth/v1/user" and req.headers["authorization"] == "Bearer AT9"
        return httpx.Response(200, json={"id": "u1", "email": "a@example.com"})

    api, _ = make(handler)
    api.recover("a@example.com", LANDED_URL)
    assert api.session == {"access_token": "AT9", "refresh_token": "RT9",
                           "user": {"id": "u1", "email": "a@example.com"}}


def test_recover_with_a_code():
    def handler(req):
        assert json.loads(req.content) == {"type": "recovery", "email": "a@example.com", "token": "123456"}
        return httpx.Response(200, json=session(4))

    api, _ = make(handler)
    api.recover("a@example.com", " 123 456 ")
    assert api.user_id == "u1"


@pytest.mark.parametrize("junk", ["", "hello", "https://example.com/page", "http://localhost:3000/#error=access_denied"])
def test_recover_rejects_anything_else_without_calling_the_server(junk):
    def handler(req):
        raise AssertionError("no request expected")

    api, _ = make(handler)
    with pytest.raises(ApiError) as e:
        api.recover("a@example.com", junk)
    assert "link" in str(e.value).lower()


def test_query_params_and_anon_calls():
    def handler(req):
        assert req.url.path == "/functions/v1/privacy"
        assert req.headers["authorization"] == "Bearer pub-key"
        assert req.url.params["x"] == "1"
        return httpx.Response(200, json=[1, 2])

    api, _ = make(handler)
    assert api.call("privacy", params={"x": 1}, anon=True) == [1, 2]
