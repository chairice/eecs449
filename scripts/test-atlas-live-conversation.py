"""Opt-in live Atlas conversation regression; six real provider requests maximum.

Run only against a ready local dev server with provider calls authorized:
  python3 scripts/test-atlas-live-conversation.py --run-live
Responses and assertion results are saved beneath /tmp without credentials.
"""
import argparse
import copy
import json
import re
import tempfile
import time
import urllib.request
from datetime import date, timedelta
from pathlib import Path


MIXED_REQUEST = "I want to fly from DTW to SFO, come back to XNA and drive to Ann Arbor a few days later"


class LiveConversation:
    def __init__(self, base_url, output):
        self.base_url = base_url.rstrip("/")
        self.output = output
        self.calls = 0
        self.last_finished = None
        self.results = []

    def ask(self, name, text, current=None):
        if self.calls >= 6:
            raise AssertionError("Live request budget exceeded")
        if self.last_finished is not None:
            time.sleep(max(0, 2.1 - (time.monotonic() - self.last_finished)))
        context = copy.deepcopy(current) if current is not None else None
        if context is not None:
            context.setdefault("conversation", []).append({"role": "user", "content": text})
        args = {"text": text, "current_json": json.dumps(context) if context is not None else ""}
        request = urllib.request.Request(
            self.base_url + "/function/atlas_interpret", data=json.dumps(args).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        self.calls += 1
        record = {"name": name, "request": args}
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                wrapper = json.load(response)
            record["response"] = wrapper
            assert wrapper.get("ok"), "RPC rejected request: " + json.dumps(wrapper)
            value = wrapper["data"]["result"]
            result = json.loads(value) if isinstance(value, str) else value
            assert result.get("source") == "llm", "Expected live model proposal: " + json.dumps(result)
            proposal = result.get("proposal")
            assert isinstance(proposal, dict), "Missing proposal"
            assert proposal["status"] == "PLANNED", "Unexpected status change"
            assert len(proposal["legs"]) == max(0, len(proposal["stops"]) - 1), "Disconnected trajectory"
            history = context.get("conversation", []) if context is not None else [{"role": "user", "content": text}]
            proposal["conversation"] = history + [{"role": "assistant", "content": " ".join(proposal["unresolved"]) or "Your route is mapped."}]
            return proposal
        except Exception as exc:
            record["error"] = str(exc)
            raise
        finally:
            self.last_finished = time.monotonic()
            (self.output / f"{self.calls:02d}-{name}.json").write_text(json.dumps(record, indent=2) + "\n")

    def chain(self, name, run):
        try:
            run()
            self.results.append({"name": name, "passed": True})
            print("PASS", name, flush=True)
        except Exception as exc:
            self.results.append({"name": name, "passed": False, "error": str(exc)})
            print("FAIL", name, str(exc), flush=True)


def assert_route(proposal, stops, modes):
    actual = [stop["query"] for stop in proposal["stops"]]
    assert len(actual) == len(stops), f"Expected {stops}; received {actual}"
    for wanted, received in zip(stops, actual):
        if wanted == "Ann Arbor":
            assert "ann arbor" in received.lower(), actual
        else:
            assert re.search(r"\b" + re.escape(wanted) + r"\b", received, re.I), actual
    assert [leg["mode"] for leg in proposal["legs"]] == modes, proposal["legs"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-live", action="store_true", help="Explicitly enable real provider calls")
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--today", type=date.fromisoformat, default=date.today(), help="Server-local date for relative-date expectations")
    args = parser.parse_args()
    if not args.run_live:
        parser.error("Pass --run-live only after the local server is ready and live calls are authorized")
    output = Path(tempfile.mkdtemp(prefix="atlas-live-conversation-", dir="/tmp"))
    print("Evidence:", output, flush=True)
    suite = LiveConversation(args.base_url, output)
    monday = args.today + timedelta(days=(0 - args.today.weekday()) % 7 or 7)
    friday = monday + timedelta(days=4)
    driving = friday + timedelta(days=3)
    expected_dates = [monday.isoformat(), friday.isoformat(), driving.isoformat()]

    def mixed_route():
        current = suite.ask("mixed-route", MIXED_REQUEST)
        assert_route(current, ["DTW", "SFO", "XNA", "Ann Arbor"], ["FLIGHT", "FLIGHT", "DRIVE"])
        assert all(not leg["departDate"] for leg in current["legs"]), "Invented initial departure dates"
        assert any(re.search(r"date|day|when", q, re.I) and "?" in q for q in current["unresolved"]), "Missing flight-date question"
        current = suite.ask("relative-dates", "The first flight is next Monday, the second flight is the following Friday, and I drive three days after the second flight.", current)
        assert_route(current, ["DTW", "SFO", "XNA", "Ann Arbor"], ["FLIGHT", "FLIGHT", "DRIVE"])
        assert [leg["departDate"] for leg in current["legs"]] == expected_dates, current["legs"]
        assert all(not leg["departTime"] and not leg["arriveTime"] for leg in current["legs"]), "Invented schedule times"
        current = suite.ask("replace-airport", "Use OAK instead of SFO", current)
        assert_route(current, ["DTW", "OAK", "XNA", "Ann Arbor"], ["FLIGHT", "FLIGHT", "DRIVE"])
        assert [leg["departDate"] for leg in current["legs"]] == expected_dates, "Replacement erased dates"
        current = suite.ask("remove-drive", "Remove the driving leg to Ann Arbor; end the journey at XNA.", current)
        assert_route(current, ["DTW", "OAK", "XNA"], ["FLIGHT", "FLIGHT"])
        assert [leg["departDate"] for leg in current["legs"]] == expected_dates[:2], "Removal changed remaining dates"

    def unknown_origin():
        current = suite.ask("unknown-origin", "I want to fly to SFO next Monday")
        assert any(re.search(r"origin|depart|from|leav|start", q, re.I) and "?" in q for q in current["unresolved"]), "Missing origin question"
        assert not any(stop["query"] in {"DTW", "JFK", "LAX", "ORD"} for stop in current["stops"]), "Invented origin airport"
        current = suite.ask("answer-origin", "DTW", current)
        assert_route(current, ["DTW", "SFO"], ["FLIGHT"])
        assert current["legs"][0]["departDate"] == monday.isoformat(), "Original relative date lost"
        assert not any(re.search(r"which.*(?:origin|depart|from)|where.*(?:depart|from|leav|start)", q, re.I) for q in current["unresolved"]), "Answered origin question persists"

    suite.chain("mixed route, dates, airport correction, drive removal", mixed_route)
    suite.chain("unknown origin followed by short answer", unknown_origin)
    summary = {"today": args.today.isoformat(), "requests": suite.calls, "results": suite.results}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if all(item["passed"] for item in suite.results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
