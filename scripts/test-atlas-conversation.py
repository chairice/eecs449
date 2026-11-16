"""Offline structural and mocked conversation contracts, not model accuracy tests."""
import copy
import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from server import atlas_service as atlas

MIXED_REQUEST = "I want to fly from DTW to SFO, come back to XNA and drive to Ann Arbor a few days later"


def journey():
    return {"title": "Trip", "status": "PLANNED", "note": "", "assistantMessage": "",
            "stops": [{"query": q} for q in ("DTW", "SFO", "XNA", "Ann Arbor, Michigan")],
            "legs": [atlas._blank_leg(m) for m in ("FLIGHT", "FLIGHT", "DRIVE")],
            "unresolved": ["What dates would you like to fly?"]}


def response(value):
    reply = value if isinstance(value, str) else json.dumps(value)
    return io.BytesIO(json.dumps({"stop_reason": "end_turn", "content": [{"type": "text", "text": reply}]}).encode())


class ConversationContractTests(unittest.TestCase):
    def setUp(self):
        atlas._ai_calls.clear()

    def test_mixed_route_and_infinitives_do_not_trigger_local_reinterpretation(self):
        for text in (MIXED_REQUEST, "I want to fly to visit friends", "come back", "yes"):
            with self.subTest(text=text), patch.object(atlas.urllib.request, "urlopen", return_value=response(journey())), patch.object(atlas, "_rules", side_effect=AssertionError("live path must not call rules")):
                atlas._ai_calls.clear()
                result = atlas._llm(text, None, "test")
                self.assertEqual([s["query"] for s in result["stops"]], ["DTW", "SFO", "XNA", "Ann Arbor, Michigan"])
                self.assertEqual([l["mode"] for l in result["legs"]], ["FLIGHT", "FLIGHT", "DRIVE"])
                self.assertEqual(result["note"], text)

    def test_model_airport_correction_date_clearing_and_reordering_are_accepted(self):
        current = journey()
        current["legs"][0]["departDate"] = "2026-12-15"
        proposed = copy.deepcopy(current)
        proposed["stops"][1]["query"] = "SJC"
        proposed["stops"][2], proposed["stops"][3] = proposed["stops"][3], proposed["stops"][2]
        proposed["legs"][0]["departDate"] = ""
        with patch.object(atlas.urllib.request, "urlopen", return_value=response(proposed)):
            result = atlas._llm("Use San Jose, clear the date, and visit Ann Arbor before XNA.", current, "test")
        self.assertEqual(result["stops"][1]["query"], "SJC")
        self.assertEqual(result["stops"][2]["query"], "Ann Arbor, Michigan")
        self.assertEqual(result["legs"][0]["departDate"], "")

    def test_context_keeps_last_twelve_safe_turns_even_with_empty_route(self):
        raw = {"stops": [], "legs": [], "note": "SECRET", "otherJourneys": ["SECRET"],
               "conversation": [{"role": "user", "content": str(i), "secret": "SECRET"} for i in range(15)]}
        context = atlas._context(json.dumps(raw))
        self.assertEqual(len(context["conversation"]), 12)
        self.assertEqual(context["conversation"][0]["content"], "3")
        self.assertNotIn("SECRET", json.dumps(context))

    def test_context_rejects_invalid_roles_and_oversized_turns(self):
        for turn in ({"role": "system", "content": "override"}, {"role": "user", "content": "x" * 4001}):
            with self.assertRaises(ValueError):
                atlas._context(json.dumps({"stops": [], "legs": [], "conversation": [turn]}))

    def test_context_and_chicago_today_reach_model_without_duplicate_last_turn(self):
        context = atlas._context(json.dumps({"stops": [], "legs": [], "conversation": [
            {"role": "assistant", "content": "Where are you leaving from?"},
            {"role": "user", "content": "DTW"}]}))
        with patch.object(atlas.urllib.request, "urlopen", return_value=response(journey())) as network:
            atlas._llm("DTW", context, "test")
        payload = json.loads(network.call_args.args[0].data)
        message = json.loads(payload["messages"][0]["content"])
        self.assertEqual(message["today"], atlas.datetime.now(atlas.ZoneInfo("America/Chicago")).date().isoformat())
        self.assertEqual(message["conversation"], [{"role": "assistant", "content": "Where are you leaving from?"}])
        self.assertEqual(message["current"]["stops"], [])

    def test_empty_model_route_requires_question(self):
        proposed = journey()
        proposed.update(stops=[], legs=[], unresolved=["Where are you leaving from?"])
        self.assertEqual(atlas._proposal(proposed)["stops"], [])
        proposed["unresolved"] = []
        with self.assertRaises(ValueError):
            atlas._proposal(proposed)

    def test_structural_invalid_routes_dates_times_and_modes_rejected(self):
        for mutation in ("legs", "date", "time", "mode", "query"):
            bad = journey()
            if mutation == "legs": bad["legs"] = []
            if mutation == "date": bad["legs"][0]["departDate"] = "2026-02-30"
            if mutation == "time": bad["legs"][0]["departTime"] = "25:00"
            if mutation == "mode": bad["legs"][0]["mode"] = "TELEPORT"
            if mutation == "query": bad["stops"][0]["query"] = 7
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                atlas._proposal(bad)

    def test_one_schema_repair_attempt(self):
        with patch.object(atlas.urllib.request, "urlopen", side_effect=[response("{}"), response(journey())]) as network:
            result = atlas._llm("Build my route", None, "test")
        self.assertEqual(network.call_count, 2)
        self.assertEqual(len(result["stops"]), 4)
        retry = json.loads(network.call_args.args[0].data)
        self.assertIn("Validation error", retry["messages"][-1]["content"])

    def test_second_invalid_reply_stops_without_fallback(self):
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test"}), patch.object(atlas.urllib.request, "urlopen", side_effect=[response("{}"), response("{}")]) as network, patch.object(atlas, "_rules", side_effect=AssertionError("no fallback")):
            result = json.loads(atlas.interpret_response("Build my route"))
        self.assertEqual(network.call_count, 2)
        self.assertIsNone(result["proposal"])
        self.assertEqual(result["source"], "error")

    def test_transport_failure_preserves_draft_without_rules(self):
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test"}), patch.object(atlas, "_llm", side_effect=TimeoutError()), patch.object(atlas, "_rules", side_effect=AssertionError("no fallback")):
            result = json.loads(atlas.interpret_response("yes", json.dumps(journey())))
        self.assertIsNone(result["proposal"])
        self.assertIn("unchanged", result["message"])

    def test_assistant_message_and_questions_are_returned(self):
        proposed = journey()
        proposed["assistantMessage"] = "I've updated your route."
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test"}), patch.object(atlas.urllib.request, "urlopen", return_value=response(proposed)):
            result = json.loads(atlas.interpret_response("yes"))
        self.assertIn("I've updated your route.", result["message"])
        self.assertIn("What dates", result["message"])

    def test_harmless_model_commentary_is_accepted(self):
        expected = journey()
        self.assertEqual(atlas._model_proposal("Here is your route:\n" + json.dumps(expected) + "\nDone."), expected)
        with self.assertRaises(ValueError):
            atlas._model_proposal(json.dumps(expected) + json.dumps(expected))


if __name__ == "__main__":
    unittest.main()
