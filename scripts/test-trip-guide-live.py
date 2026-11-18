#!/usr/bin/env python3
"""Opt-in offsite research -> saved agenda regression in an isolated ledger.

Uses real configured model/browser services. Fixture commitments are explicitly
user-supplied test inputs, never researched inventory or actual bookings.
"""
import argparse
import copy
import json
import os
import sys
import tempfile
from pathlib import Path

# This opt-in driver claims its own isolated jobs; never start a second worker.
os.environ["DETOUR_EMBEDDED_WORKER"] = "off"

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "web"), str(ROOT / "workers")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-live", action="store_true", required=True)
    args = parser.parse_args()
    if not args.run_live:
        return
    from dotenv import load_dotenv
    load_dotenv(ROOT / "workers/.env")
    folder = Path(tempfile.mkdtemp(prefix="detour-trip-guide-live-"))
    os.environ["PLANNER_DATA_DIR"] = str(folder)
    from atlas_runtime.planner import plan
    from server import planning_api as api, planning_jobs as jobs
    from server.planning_core import dumps, loads, uid, validate_trip

    state = api.fresh()
    state["snapshot"].update(title="San Francisco work offsite", intent="BUSINESS", detail="LOGISTICS",
        startDate="2026-11-22", endDate="2026-11-25",
        places=[{"id": "sf", "label": "San Francisco", "query": "San Francisco, California", "kind": "CITY", "lat": 37.7749, "lon": -122.4194, "timezone": "America/Los_Angeles"},
                {"id": "sfo", "label": "San Francisco (SFO)", "query": "San Francisco International Airport SFO", "kind": "AIRPORT", "lat": 37.6213, "lon": -122.379, "timezone": "America/Los_Angeles"},
                {"id": "xna", "label": "Northwest Arkansas (XNA)", "query": "Northwest Arkansas National Airport XNA", "kind": "AIRPORT", "lat": 36.2819, "lon": -94.3068, "timezone": "America/Chicago"}],
        legs=[{"id": "fixed-return", "fromId": "sfo", "toId": "xna", "mode": "FLIGHT", "departDate": "2026-11-25", "departTime": "07:00", "arriveDate": "2026-11-25", "arriveTime": "15:28", "durationMinutes": 388, "locked": True, "notes": "User-provided schedule fixture; no fare or booking asserted."}],
        days=[{"id": "unrelated-day", "date": "2026-11-24", "title": "Existing work commitment", "items": [{"id": "fixed-meeting", "title": "Client meeting", "kind": "ACTIVITY", "placeId": "sf", "startTime": "13:00", "endTime": "14:00", "locked": True, "notes": "User-provided test commitment."}]}])
    state["snapshot"] = validate_trip(state["snapshot"])
    original = copy.deepcopy(state["snapshot"])
    request = {"tripId": state["id"], "snapshot": state["snapshot"], "baseRevision": 0, "clientTurnId": uid("turn"),
        "today": "2026-11-16", "timeZone": "America/Los_Angeles",
        "message": "Plan a practical outdoor team offsite for eight people on Monday November 23, 2026 in San Francisco: pick up rental bikes near Fisherman's Wharf, ride across Golden Gate Bridge to Sausalito, lunch there, and return by ferry. Research actual bike rental/group and return arrangements, that day's ferry schedule and bike rules, lunch options for eight, and a useful rain alternative. Add this to the saved itinerary with usable public source links. Do not invent availability, schedules, prices or opening hours: identify the remaining arrangements clearly. Keep daylight and weather tied to November 23, not Sunday's forecast. Preserve my fixed return flight, existing November 24 day and trip dates. This is still a logistics-focused business trip; only the offsite group has eight people. Do not search flights/hotels, log in, reserve or pay. Avoid optional budget questions; make sensible researched suggestions."}
    request = loads(api.prepare_request(dumps(state), dumps(request)))
    owner = "account:isolated-trip-guide-live"
    job_id = jobs.enqueue(owner, dumps(request))
    state = loads(api.record_job(dumps(state), dumps(request), job_id))
    claimed = jobs.claim("isolated-trip-guide-test")
    result = plan(request, owner, update=lambda message: print(message, flush=True))
    jobs.finish(job_id, claimed["lease_token"], result)
    state = api.stage(dumps(state), owner, job_id)
    (folder / "evidence.json").write_text(json.dumps({"request": request, "result": result, "state": state}, indent=2))
    offsite = [day for day in state["snapshot"]["days"] if day["date"] == "2026-11-23"]
    checks = {
        "offsite_saved": bool(offsite and len(offsite[0]["items"]) >= 4),
        "fixed_flight_preserved": state["snapshot"]["legs"] == original["legs"],
        "unrelated_day_preserved": next((d for d in state["snapshot"]["days"] if d["id"] == "unrelated-day"), None) == original["days"][0],
        "trip_dates_preserved": all(state["snapshot"][key] == original[key] for key in ["startDate", "endDate"]),
        "travel_party_preserved": state["snapshot"]["party"] == original["party"],
        "logistics_setting_preserved": state["snapshot"]["detail"] == "LOGISTICS",
        "actual_research": result.get("sourceCount", 0) >= 3,
        "usable_source_actions": bool(offsite and any(item.get("actions") for item in offsite[0]["items"])),
        "no_invented_booking": not state["snapshot"]["bookings"],
        "no_unrequested_inventory": not state["offers"],
    }
    (folder / "summary.json").write_text(json.dumps({"checks": checks, "sourceCount": result.get("sourceCount", 0), "evidence": str(folder)}, indent=2))
    print(json.dumps({"checks": checks, "sourceCount": result.get("sourceCount", 0), "evidence": str(folder)}), flush=True)
    assert all(checks.values()), "Offsite usefulness acceptance failed; inspect the retained evidence."


if __name__ == "__main__":
    main()
