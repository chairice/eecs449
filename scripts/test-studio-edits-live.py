#!/usr/bin/env python3
"""Opt-in live model→validated stage→Undo→conversational decision regression.

Uses an isolated temporary ledger. Does not edit a person's saved Jac trips.
The date anchor is explicit; observed outputs are retained for inspection.
"""
import argparse
import copy
import json
import os
import tempfile
from pathlib import Path

from dotenv import load_dotenv
from atlas_runtime.planner import plan
from server import planning_api as api, planning_jobs as jobs
from server.planning_core import validate_trip, dumps, loads, uid
from server.planning_lifecycle import undo_json

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-live", action="store_true", required=True)
    args = parser.parse_args()
    if not args.run_live: return
    load_dotenv(ROOT / "workers/.env")
    folder = tempfile.mkdtemp(prefix="detour-edits-live-")
    os.environ["PLANNER_DATA_DIR"] = folder
    state = api.fresh()
    state["snapshot"].update(title="San Francisco breathing room", startDate="2026-11-22", endDate="2026-11-22", detail="DETAILED",
        places=[{"id": "sf", "query": "San Francisco, CA", "kind": "CITY", "lat": 37.7749, "lon": -122.4194, "timezone": "America/Los_Angeles"}],
        stays=[{"id": "stay", "placeId": "sf", "checkIn": "2026-11-22", "checkOut": "2026-11-23"}],
        days=[{"id": "day1", "date": "2026-11-22", "title": "A full San Francisco day", "overnightPlaceId": "sf", "items": [
            {"id": "morning", "title": "Explore the waterfront", "kind": "ACTIVITY", "placeId": "sf", "startTime": "09:00", "endTime": "12:00"},
            {"id": "afternoon", "title": "Explore local neighborhoods", "kind": "ACTIVITY", "placeId": "sf", "startTime": "13:00", "endTime": "17:00"},
            {"id": "evening", "title": "Dinner and a walk", "kind": "ACTIVITY", "placeId": "sf", "startTime": "18:00", "endTime": "21:00"}]}])
    state["snapshot"] = validate_trip(state["snapshot"])
    original = copy.deepcopy(state["snapshot"])
    evidence = []

    def turn(message):
        nonlocal state
        request = {"tripId": state["id"], "snapshot": state["snapshot"], "baseRevision": state["revision"],
                   "message": message, "clientTurnId": uid("turn"), "today": "2026-11-15", "timeZone": "America/Detroit"}
        request = loads(api.prepare_request(dumps(state), dumps(request)))
        job_id = jobs.enqueue("account:live-edits", dumps(request))
        state = loads(api.record_job(dumps(state), dumps(request), job_id))
        job = jobs.claim("isolated-live-test")
        result = plan(request, "account:live-edits", update=lambda text: print(text, flush=True))
        jobs.finish(job_id, job["lease_token"], result)
        state = api.stage(dumps(state), "account:live-edits", job_id)
        evidence.append({"message": message, "result": result, "state": copy.deepcopy(state)})
        Path(folder, "evidence.json").write_text(json.dumps(evidence, indent=2))
        return result

    turn("Add a 30-minute rest break at noon on November 22. Keep every existing activity and the other timing unchanged. No research needed.")
    assert state["revision"] == 1 and state["pending"] is None
    rest = [i for i in state["snapshot"]["days"][0]["items"] if i["kind"] == "REST"]
    assert rest and rest[0]["startTime"] == "12:00"
    assert {i["id"] for i in original["days"][0]["items"]}.issubset({i["id"] for i in state["snapshot"]["days"][0]["items"]})
    state = loads(undo_json(dumps(state), 1, "live-undo"))
    assert state["snapshot"] == original and state["revision"] == 2
    turn("This feels rushed. Would another night help? Suggest a concrete extra-night version that keeps all three activities, but ask me before changing the trip dates. No web research needed.")
    assert state["pending"] and state["snapshot"] == original, "An unrequested date change must become a plain chat question"
    pending = copy.deepcopy(state["pending"])
    assert pending["question"] in state["conversation"][-1]["content"]
    turn("Yes, use that extra-night version you just suggested.")
    assert state["pending"] is None and state["revision"] == 3
    assert state["snapshot"]["endDate"] == pending["snapshot"]["endDate"]
    assert state["snapshot"]["endDate"] != original["endDate"]
    print(json.dumps({"passed": True, "checks": ["automatic rest break", "revision-bound Undo", "consequential chat question", "answer binds current decision"], "evidence": folder}))


if __name__ == "__main__": main()
