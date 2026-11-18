#!/usr/bin/env python3
"""Opt-in semantic regression using the configured Anthropic model and credits.

Run from repository root with PYTHONPATH=workers:web workers/.venv/bin/python.
No user trip is modified. Outputs contain synthetic test-trip data only.
"""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from dotenv import load_dotenv
from atlas_runtime.planner import plan
from server.planning_core import blank_trip, uid, validate_trip

load_dotenv(Path(__file__).resolve().parents[1] / "workers/.env")


def initial():
    trip = blank_trip(uid("live_test"))
    return {"tripId": trip["id"], "snapshot": trip, "baseRevision": 0, "today": "2026-11-14", "timeZone": "America/Detroit",
            "conversation": [], "workingContext": {}, "summary": "", "preferences": {}, "attachments": []}


def turn(request, message, approve=False):
    request["message"] = message
    result = plan(request, "local-live-semantic-test", update=lambda message: print("  " + message, flush=True), publish=lambda snapshot: Path("/tmp/atlas-live-working-preview.json").write_text(json.dumps(snapshot)))
    request["conversation"] += [{"role": "user", "content": message}, {"role": "assistant", "content": result["assistantMessage"]}]
    request["workingContext"] = result["workingContext"]; request["summary"] = result["summary"]
    if approve:
        request["snapshot"] = result["proposed"]; request["baseRevision"] += 1
    Path("/tmp/atlas-live-last-turn.json").write_text(json.dumps(result, indent=2))
    print(result["assistantMessage"], flush=True)
    return result


def mixed():
    request = initial()
    first = turn(request, "I want to fly from DTW to SFO, then fly back to XNA and drive to Ann Arbor a few days later. Start with the route; don't research flights yet.", approve=True)
    assert [leg["mode"] for leg in first["proposed"]["legs"]] == ["FLIGHT", "FLIGHT", "DRIVE"]
    assert len(first["proposed"]["places"]) == 4
    assert all(not leg["departDate"] for leg in first["proposed"]["legs"])
    second = turn(request, "I've approved that route. Leave DTW next Friday, stay three nights in San Francisco, fly SFO to XNA the following Monday, spend one night there, then drive to Ann Arbor. Two adults. Don't research inventory yet.", approve=True)
    assert [leg["departDate"] for leg in second["proposed"]["legs"]] == ["2026-11-20", "2026-11-23", "2026-11-24"], second["proposed"]["legs"]
    assert second["proposed"]["party"]["adults"] == 2
    third = turn(request, "Keep this logistics only, with no activities. We prefer hotels with free parking; remember that for future trips. Still no inventory research.")
    assert third["proposed"]["detail"] == "LOGISTICS"
    assert [leg["mode"] for leg in third["proposed"]["legs"]] == ["FLIGHT", "FLIGHT", "DRIVE"]
    assert not third["offers"]
    assert all(item["kind"] in {"TRAVEL", "LODGING"} for day in third["proposed"]["days"] for item in day["items"])
    return {"scenario": "mixed", "passed": True, "turns": [first, second, third]}


def business():
    request = initial()
    result = turn(request, "A professional trip: fly DTW to Seattle November 30 to December 2, 2026. One adult. I only need flights and a hotel, no sightseeing itinerary. Don't search live offers yet; propose the travel structure first.")
    snapshot = result["proposed"]
    assert snapshot["intent"] == "BUSINESS" and snapshot["detail"] == "LOGISTICS"
    assert all(item["kind"] in {"TRAVEL", "LODGING"} for day in snapshot["days"] for item in day["items"])
    assert snapshot["startDate"] == "2026-11-30" and snapshot["endDate"] == "2026-12-02"
    assert snapshot["party"]["adults"] == 1
    return {"scenario": "business", "passed": True, "turns": [result]}


def arizona():
    request = initial()
    source = (Path(__file__).resolve().parents[1] / "workers/tests/fixtures/arizona-user-itinerary.txt").read_text()
    result = turn(request, "Import my existing detailed Arizona itinerary, December 26, 2026 through January 4, 2027. Preserve all ten days, stops, supplied times, drive-time notes and buffers, rest breaks, optional alternatives and missing-out notes. This is an existing plan, so don't replace it with a rough outline. Do not browse for hours or inventory yet. Identify contradictions using the supplied notes, and keep external facts and timings provisional.\n\n" + source)
    snapshot = result["proposed"]
    assert len(snapshot["days"]) == 10
    assert snapshot["days"][0]["date"] == "2026-12-26" and snapshot["days"][-1]["date"] == "2027-01-04"
    corpus = json.dumps(snapshot).lower()
    for landmark in ["chiricahua", "white pocket", "walnut canyon", "horseshoe", "antelope", "meteor", "sedona", "tucson"]:
        assert landmark in corpus, "Lost imported location: " + landmark
    narrative = (result["assistantMessage"] + " " + " ".join(result.get("warnings", []))).lower()
    assert "meteor" in narrative and any(word in narrative for word in ["close", "closing", "conflict"]), "Missed supplied Meteor Crater closing-time conflict"
    assert result["sourceCount"] == 0 and not result["offers"]
    return {"scenario": "arizona", "passed": True, "turns": [result]}


def day_order():
    request = initial()
    snapshot = request["snapshot"]
    snapshot.update(title="Tucson day ordering", startDate="2026-12-27", endDate="2026-12-27")
    snapshot["places"] = [{"id": "tucson", "query": "Tucson, AZ", "label": "Tucson base", "kind": "CITY"}]
    snapshot["days"] = [{"id": "day27", "date": "2026-12-27", "title": "Easy hikes and sunset", "items": [
        {"id": "morning", "title": "Easy morning walk"}, {"id": "sunset", "title": "Sunset at Gates Pass"},
        {"id": "rest", "title": "Rest at Tucson base", "kind": "REST", "placeId": "tucson", "startTime": "14:00", "endTime": "16:00"}]}]
    request["snapshot"] = validate_trip(snapshot)
    before = request["snapshot"]["days"][0]["items"]
    result = turn(request, "On December 27 put the existing 2–4 PM rest break before the Gates Pass sunset stop. Keep every activity, time and other detail unchanged. Just reorder the existing items; do not research. This is only for this trip.")
    after = result["proposed"]["days"][0]["items"]
    assert [item["id"] for item in after] == ["morning", "rest", "sunset"]
    assert {item["id"]: item for item in before} == {item["id"]: item for item in after}
    assert not result["memoryUpdates"] and not result["offers"] and result["sourceCount"] == 0
    return {"scenario": "day_order", "passed": True, "turns": [result]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", choices=["mixed", "business", "arizona", "day_order", "all"], default="all")
    parser.add_argument("--output", default="/tmp/atlas-live-semantic-results.json")
    args = parser.parse_args()
    results = []
    for name in (["mixed", "business"] if args.scenario == "all" else [args.scenario]):
        print("Scenario: " + name, flush=True)
        results.append(globals()[name]())
        Path(args.output).write_text(json.dumps(results, indent=2))
        print("PASS: " + name, flush=True)


if __name__ == "__main__":
    main()
