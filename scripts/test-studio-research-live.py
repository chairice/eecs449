#!/usr/bin/env python3
"""Real browser acceptance. A search-link fallback never passes option coverage.

Runs isolated test requests using existing local model credits. Captures remain
private under PLANNER_DATA_DIR/evidence; summaries contain no credentials.
"""
import argparse
import copy
import json
import os
from pathlib import Path
from dotenv import load_dotenv
from atlas_runtime.planner import plan
from server.planning_core import blank_trip, uid

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / "workers/.env")
MESSAGES = {
    "combined": "Research only: find real one-way economy flights DTW to SFO on November 22, 2026, then SFO to XNA on November 25, 2026, and a San Francisco hotel November 22–25, 2026 for one adult, zero children, one room. No budget or neighborhood preference; do not ask optional questions. Research every flight leg and the hotel independently. Show up to two real relevant options per component with observed prices, clear unit/starting basis, real flight times/stops where available, and observed provider handoff pages. Make meaningful attempts to correct date/traveler controls and try another source when necessary. Google Hotels often ignores URL dates: inspect and fix active controls before using its prices. Do not edit the trip. No login or booking.",
    "flight": "Research only, no itinerary edits. Find a one-way economy flight DTW to SFO on November 22, 2026 for one adult and zero children. No fixed budget. Up to three real relevant options with observed prices and clear price bases. Use actual provider results and inspect search controls. A provider results page is a valid handoff. No login or booking.",
    "hotel": "Research only, no itinerary edits. Find a San Francisco hotel November 22–25, 2026 for one adult, zero children, one room. No fixed budget or neighborhood requirement. Up to three real hotel options with observed starting/unit/stay prices, correct price bases and actual area. Inspect the active hotel date and traveler controls; fix them if they do not match. No login or booking.",
    "airbnb": "Research only, no itinerary edits. Find real Airbnb stays in San Francisco November 22–25, 2026 for one adult and zero children. No fixed budget or neighborhood requirement. Up to three relevant real Airbnb options with observed prices, correct unit or stay-total bases and location. Inspect active dates and guests before quoting. No login or booking.",
    "car": "Research only, no itinerary edits. Find a standard rental car pickup SFO airport November 22, 2026 at 12:00 local, return SFO airport November 25, 2026 at 12:00 local, one driver age 30, no membership discount. No fixed budget. Up to three real options with observed daily/starting/total price bases. Verify active airport/dates/times/driver controls. Try a second real source if needed. No login or booking.",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("category", choices=MESSAGES)
    parser.add_argument("--output")
    args = parser.parse_args()
    snapshot = blank_trip(uid("research_test"))
    request = {"tripId": snapshot["id"], "snapshot": snapshot, "baseRevision": 0, "today": "2026-11-15", "timeZone": "America/Detroit",
        "message": MESSAGES[args.category], "attachments": [], "conversation": [], "workingContext": {}, "summary": "", "preferences": {}}
    os.environ["PLANNER_CAPTURE_REJECTIONS"] = "1"
    before = copy.deepcopy(snapshot)
    result = plan(request, "local-live-research-test", update=lambda message: print(message, flush=True))
    assert snapshot == before and result["proposed"] == before and not result["operations"]
    output = Path(args.output or "/tmp/detour-live-" + args.category + "-research.json")
    output.write_text(json.dumps(result, indent=2))
    queries = [offer["query"] for offer in result["offers"]]
    if args.category == "combined":
        coverage = {"DTW-SFO": any(q.get("origin") == "DTW" and q.get("destination") == "SFO" and q.get("departDate") == "2026-11-22" for q in queries),
                    "SFO-XNA": any(q.get("origin") == "SFO" and q.get("destination") == "XNA" and q.get("departDate") == "2026-11-25" for q in queries),
                    "SF hotel": any(q.get("category") == "HOTEL" and q.get("checkIn") == "2026-11-22" and q.get("checkOut") == "2026-11-25" and q.get("adults") == 1 and q.get("rooms") == 1 for q in queries)}
    else: coverage = {args.category: bool(result["offers"])}
    print(json.dumps({"category": args.category, "sourceCount": result["sourceCount"], "offers": len(result["offers"]), "coverage": coverage,
        "components": result.get("researchComponents", []), "output": str(output)}), flush=True)
    print(result["assistantMessage"], flush=True)
    assert result["sourceCount"] > 0, "The test must actually access public browser sources"
    assert all(coverage.values()), "Incomplete real option coverage; generic search handoffs do not pass acceptance"


if __name__ == "__main__": main()
