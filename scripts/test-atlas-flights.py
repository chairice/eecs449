"""Offline contract checks: python3 scripts/test-atlas-flights.py."""
import json
import os
import sys
import unittest
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from server import atlas_flights as flights


class FlightResearchTests(unittest.TestCase):
    def setUp(self):
        flights._cache.clear()
        flights._calls.clear()
        self.day = str(date.today() + timedelta(days=10))
        self.segment = {"from": "DTW", "to": "SFO", "date": self.day}
        self.request = json.dumps({"segments": [self.segment], "passengers": 1})

    def test_modes_and_validation(self):
        self.assertEqual(flights._validate(self.request)[1], "one-way")
        returning = {"from": "SFO", "to": "DTW", "date": self.day}
        self.assertEqual(flights._validate(json.dumps({"segments": [self.segment, returning]}))[1], "round-trip")
        returning["to"] = "LAX"
        self.assertEqual(flights._validate(json.dumps({"segments": [self.segment, returning]}))[1], "multi-city")
        for bad in ({"segments": [self.segment], "passengers": True},
                    {"segments": [{**self.segment, "date": "2000-01-01"}]},
                    {"segments": [{**self.segment, "to": "ZZZ"}]},
                    {"segments": [self.segment] * 7}):
            self.assertEqual(json.loads(flights.flights_response(json.dumps(bad)))["status"], "NEEDS_DETAILS")

    def test_only_search_sources_and_citations(self):
        response = {"content": [
            {"type": "text", "text": "https://www.delta.com/invented",
             "citations": [{"type": "web_search_result_location", "url": "https://www.kayak.com/flights", "title": "Kayak"}]},
            {"type": "web_search_tool_result", "content": [
                {"type": "web_search_result", "url": "https://www.delta.com/", "title": "Delta"},
                {"type": "web_search_result", "url": "https://127.0.0.1/", "title": "Private"}]}]}
        sources = flights._sources(response)
        self.assertEqual(len(sources), 2)
        self.assertNotIn("https://www.delta.com/invented", [s["url"] for s in sources])
        for url in ("javascript:alert(1)", "https://delta.com.evil.org/", "https://www.google.com/url?q=x", "https://user:pass@delta.com/"):
            self.assertIsNone(flights._safe_url(url))

    def test_ready_cache_and_failure(self):
        response = {"content": [{"type": "web_search_tool_result", "content": [
            {"type": "web_search_result", "url": "https://www.delta.com/", "title": "Delta"}]}]}
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "secret-test-key"}), patch.object(flights, "_provider", return_value=response) as provider:
            first = flights.flights_response(self.request)
            self.assertEqual(first, flights.flights_response(self.request))
            provider.assert_called_once()
            result = json.loads(first)
            self.assertEqual(result["status"], "READY")
            self.assertEqual(result["options"][0]["priceLabel"], "Check current fare")
            self.assertNotIn("secret-test-key", first)
        flights._cache.clear()
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "secret-test-key"}), patch.object(flights, "_provider", side_effect=RuntimeError("secret-test-key")):
            result = flights.flights_response(self.request)
            self.assertEqual(json.loads(result)["status"], "ERROR")
            self.assertNotIn("secret-test-key", result)
            self.assertEqual(flights._active, 0)


if __name__ == "__main__":
    unittest.main()
