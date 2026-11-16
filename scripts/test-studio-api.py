#!/usr/bin/env python3
"""Integration checks against a running LOCAL Jac server; no travel/model calls.

Creates uniquely named test accounts and trips in the local development store.
Never prints credentials or bearer tokens.
"""
import concurrent.futures
import copy
import json
import os
import secrets
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from server.planning_api import fresh

BASE = os.environ.get("ATLAS_TEST_API", "http://localhost:8001")
if not BASE.startswith(("http://localhost:", "http://127.0.0.1:")):
    raise SystemExit("This test creates local test records; use a localhost API.")


def request(path, body, token=""):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=40) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        return exc.code, json.load(exc)


def rpc(name, args=None, token=""):
    status, envelope = request("/function/" + name, args or {}, token)
    if status != 200:
        return {"httpStatus": status, "error": "Request rejected"}
    if not envelope.get("ok"):
        raise AssertionError("RPC failed: " + name + " " + str(envelope.get("error", "")))
    value = envelope["data"]["result"]
    return json.loads(value) if isinstance(value, str) else value


def account():
    name = "atlas-local-test-" + secrets.token_hex(8) + "@example.com"
    password = secrets.token_urlsafe(24)
    status, result = request("/user/register", {"identities": [{"type": "email", "value": name}, {"type": "username", "value": name}],
        "credential": {"type": "password", "password": password}})
    assert status in {200, 201}, ("registration", status, list(result))
    status, result = request("/user/login", {"identity": {"type": "email", "value": name}, "credential": {"type": "password", "password": password}})
    assert status == 200, ("login", status, list(result))
    payload = result.get("data", result)
    token = payload.get("token") or payload.get("access_token")
    assert token, ("token missing", list(payload))
    return token


def main():
    assert rpc("planner_list").get("httpStatus") == 401
    first, second = account(), account()
    for helper in ["fresh_json", "read_json", "owner", "claim_guest", "undo_json", "weather_json",
                   "delete_json", "restore_json", "trip_summary", "_fresh_json", "_read_json", "_find_trip"]:
        # Jac's unknown POST route returns 405; signature introspection is 404.
        assert rpc(helper, token=second).get("httpStatus") in {401, 403, 404, 405}, "Internal helper exposed: " + helper
        try:
            urllib.request.urlopen(BASE + "/function/" + helper, timeout=10)
        except urllib.error.HTTPError as exc:
            assert exc.code == 404, (helper, exc.code)
        else:
            raise AssertionError("Internal helper signature exposed: " + helper)
    state = fresh()
    proposed = copy.deepcopy(state["snapshot"]); proposed["title"] = "Local transaction test"
    state["pending"] = {"id": "proposal_local", "snapshot": proposed, "warnings": []}
    token = secrets.token_urlsafe(48)
    saved = rpc("planner_import", {"state_json": json.dumps(state), "token": token}, first)
    assert not saved.get("error"), saved
    assert saved["pending"] and saved["snapshot"]["title"] == "Untitled trip"
    assert rpc("planner_get", {"trip_id": state["id"]}, second).get("error")
    assert rpc("planner_list", token=second) == []
    args = {"trip_id": state["id"], "proposal_id": "proposal_local", "revision": 0, "command_id": "approve_local"}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: rpc("planner_approve", args, first), range(2)))
    assert all(result.get("revision") == 1 for result in results), results
    assert rpc("planner_get", {"trip_id": state["id"]}, first)["revision"] == 1
    assert rpc("planner_approve", {**args, "command_id": "another_command"}, first).get("error")
    assert rpc("planner_approve", args, second).get("error")
    assert rpc("planner_import", {"state_json": json.dumps(state), "token": token}, first)["revision"] == 1
    altered = copy.deepcopy(state); altered["snapshot"]["title"] = "Different device draft"
    assert rpc("planner_import", {"state_json": json.dumps(altered), "token": token}, first).get("error")
    another = fresh(); target = copy.deepcopy(another["snapshot"]); target["title"] = "Competing approvals"
    another["pending"] = {"id": "proposal_competing", "snapshot": target, "warnings": []}
    saved = rpc("planner_import", {"state_json": json.dumps(another), "token": ""}, first)
    assert not saved.get("error"), saved
    def compete(command):
        return rpc("planner_approve", {"trip_id": another["id"], "proposal_id": "proposal_competing", "revision": 0, "command_id": command}, first)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(compete, ["competing_a", "competing_b"]))
    assert sum(result.get("revision") == 1 for result in results) == 1, results
    assert sum(bool(result.get("error")) for result in results) == 1, results
    assert rpc("planner_get", {"trip_id": another["id"]}, first)["revision"] == 1
    # The public conversation applies edits directly; retained internal revision
    # endpoints also exercise the same atomic Undo transaction without AI calls.
    before_undo = rpc("planner_get", {"trip_id": another["id"]}, first)
    undo_args = {"trip_id": another["id"], "revision": 1, "command_id": "undo_local"}
    assert rpc("planner_undo", undo_args).get("httpStatus") == 401
    assert rpc("planner_undo", undo_args, second).get("error")
    undone = rpc("planner_undo", undo_args, first)
    assert undone.get("revision") == 2, undone
    assert undone["snapshot"] == another["snapshot"]
    assert rpc("planner_undo", undo_args, first)["revision"] == 2, "Duplicate Undo must be idempotent"
    assert rpc("planner_undo", {**undo_args, "command_id": "stale_undo"}, first).get("error")
    assert before_undo["snapshot"]["title"] == "Competing approvals"

    assert rpc("planner_delete", {"trip_id": another["id"]}, second).get("error")
    deleted = rpc("planner_delete", {"trip_id": another["id"]}, first)
    assert deleted.get("deletedAt") and deleted.get("deleteReason") == "USER", deleted
    assert all(trip["id"] != another["id"] for trip in rpc("planner_list", token=first))
    assert rpc("planner_get", {"trip_id": another["id"]}, first).get("error")
    assert any(trip["id"] == another["id"] for trip in rpc("planner_deleted", token=first))
    assert rpc("planner_deleted", token=second) == []
    assert rpc("planner_restore", {"trip_id": another["id"]}, second).get("error")
    restored = rpc("planner_restore", {"trip_id": another["id"]}, first)
    assert not restored.get("deletedAt") and restored.get("retainedDraft")
    assert restored["snapshot"] == undone["snapshot"] and restored["revision"] == 2
    assert any(trip["id"] == another["id"] for trip in rpc("planner_list", token=first))
    assert all(trip["id"] != another["id"] for trip in rpc("planner_deleted", token=first))

    assert rpc("planner_weather", {"trip_id": another["id"]}).get("httpStatus") == 401
    assert rpc("planner_weather", {"trip_id": another["id"]}, second).get("error")
    weather = rpc("planner_weather", {"trip_id": another["id"]}, first)
    assert "fingerprint" in weather and isinstance(weather.get("samples"), list), weather
    print("PASS: authentication, hidden helpers, account isolation, guest import, atomic concurrent revisions, stale writes, payload-bound import, revision-bound/idempotent Undo, deletion/recovery, and auxiliary weather ownership")


if __name__ == "__main__":
    main()
