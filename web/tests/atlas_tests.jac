"""Atlas boundaries and mocked providers: no network access or paid model calls."""
import json;
import os;
import from unittest.mock { patch, MagicMock }
import server.atlas_service as svc;
import from server.atlas { atlas_status, atlas_interpret, atlas_route }

test "status reflects key presence without a provider call" {
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}) {
        assert json.loads(atlas_status())["aiAvailable"] == False;
    }
}

test "explicit routes preserve all ordered stops including repeats" {
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}) {
        result = json.loads(atlas_interpret("San Francisco -> New York -> Chicago -> San Francisco", ""));
        assert result["source"] == "rules";
        assert [x["query"] for x in result["proposal"]["stops"]] == ["San Francisco", "New York", "Chicago", "San Francisco"];
        assert len(result["proposal"]["legs"]) == 3;
    }
}

test "complex mixed-mode return prose stays wholly unresolved without AI" {
    text = "I flew from San Francisco to New York, drove to Boston, then returned to San Francisco on Friday";
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}) {
        result = json.loads(atlas_interpret(text, ""));
        assert result["proposal"]["stops"] == [];
        assert result["proposal"]["note"] == text;
        assert text in result["proposal"]["unresolved"][0];
    }
}

test "from to and then grammar does not invent modes" {
    result = svc._rules("from Ann Arbor to Chicago then Detroit", None);
    assert len(result["stops"]) == 3;
    assert result["legs"][0]["mode"] == "UNKNOWN";
}

test "partial parsing is not a successful two-city plan" {
    result = svc._rules("Seattle to Portland then maybe go back on Friday", None);
    assert result["stops"] == [];
    assert "Friday" in result["note"];
}

test "selected context strips notes history and coordinates" {
    selected = {"title": "Weekend", "status": "PAST", "note": "SECRET NOTE", "history": ["SECRET HISTORY"],
        "stops": [{"name": "Detroit", "lat": 42}, {"name": "Chicago", "lon": -87}], "legs": [svc._blank_leg("DRIVE")]};
    result = svc._context(json.dumps(selected));
    assert result["note"] == "";
    assert "SECRET" not in json.dumps(result);
    assert "lat" not in json.dumps(result) and "history" not in json.dumps(result);
}

test "unrecognized followups preserve selected stops and leg details" {
    selected = {"title": "Weekend", "status": "PAST", "stops": [{"query": "Detroit"}, {"query": "Chicago"}], "legs": [svc._blank_leg("DRIVE")]};
    selected["legs"][0]["departDate"] = "2026-10-12";
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}) {
        result = json.loads(atlas_interpret("leave an hour later", json.dumps(selected)));
        assert result["proposal"]["legs"][0]["departDate"] == "2026-10-12";
        assert result["proposal"]["legs"][0]["mode"] == "DRIVE";
        assert result["proposal"]["status"] == "PAST";
    }
}

test "oversized and malformed context inputs do not mutate a proposal" {
    assert json.loads(atlas_interpret("x" * 4001, ""))["proposal"] is None;
    assert json.loads(atlas_interpret("Detroit to Chicago", "[]"))["proposal"] is None;
    assert json.loads(atlas_interpret("Detroit to Chicago", "{"))["proposal"] is None;
}

test "malformed model stop and leg shapes are rejected as a whole" {
    bad = {"title": "Trip", "status": "PLANNED", "stops": [{"query": "Detroit"}, {"query": "Chicago"}], "legs": []};
    failed = False;
    try { _ = svc._proposal(bad); } except ValueError { failed = True; }
    assert failed;
    bad["legs"] = [svc._blank_leg()];
    bad = json.loads('{"title":"Trip","status":"PLANNED","stops":[{"query":42}],"legs":[]}');
    failed = False;
    try { _ = svc._proposal(bad); } except ValueError { failed = True; }
    assert failed;
}

test "provider failure is honestly marked rules and keeps original text" {
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-only-not-a-key"}), patch.object(svc, "_llm", side_effect=ValueError("truncated")) {
        result = json.loads(atlas_interpret("Detroit to Chicago", ""));
        assert result["source"] == "rules";
        assert "could not" in result["message"];
        assert result["proposal"]["note"] == "Detroit to Chicago";
    }
}

test "truncated model envelopes are rejected without trusting partial text" {
    response = MagicMock();
    response.__enter__.return_value = response;
    response.read.return_value = b'{"stop_reason":"max_tokens","content":[{"type":"text","text":"{}"}]}';
    with patch.object(svc.urllib.request, "urlopen", return_value=response), patch.object(svc, "_ai_calls", svc.deque()) {
        failed = False;
        try { _ = svc._llm("Detroit to Chicago", None, "test-only"); } except ValueError { failed = True; }
        assert failed;
    }
}

test "model cannot silently drop a repeated return leg" {
    proposal = svc._rules("San Francisco to New York", None);
    failed = False;
    try { svc._check_preserved("fly to New York then return to San Francisco", None, proposal); } except ValueError { failed = True; }
    assert failed;
}

test "route rejects arbitrary URLs IDs and unsupported mainland Alaska trips" {
    places = {"detroit": {"id": "detroit", "state": "MI", "lat": 42.3, "lon": -83.0}, "anchorage": {"id": "anchorage", "state": "AK", "lat": 61.2, "lon": -149.9}};
    with patch.object(svc, "_by_id", return_value=places), patch.object(svc.urllib.request, "urlopen") as network {
        assert json.loads(atlas_route("http://127.0.0.1", "detroit"))["status"] == "ERROR";
        assert json.loads(atlas_route("detroit", "anchorage"))["status"] == "ERROR";
        assert json.loads(atlas_route("detroit", "detroit"))["status"] == "ERROR";
        network.assert_not_called();
    }
}

test "route cache avoids repeat requests and rate gate returns immediately" {
    places = {"a": {"state": "MI"}, "b": {"state": "IL"}, "c": {"state": "NY"}};
    ready = json.dumps({"status": "READY", "points": [[42, -83], [41, -87]]});
    with patch.object(svc, "_by_id", return_value=places), patch.object(svc, "_route_cache", svc.OrderedDict()), patch.object(svc, "_last_route", -100.0), patch.object(svc.time, "monotonic", return_value=100.0), patch.object(svc, "_route_fetch", return_value=ready) as provider {
        assert json.loads(atlas_route("a", "b"))["status"] == "READY";
        assert json.loads(atlas_route("a", "b"))["status"] == "READY";
        assert json.loads(atlas_route("a", "c"))["status"] == "ERROR";
        assert provider.call_count == 1;
    }
}

test "route cache has a fixed entry bound" {
    places = {str(i): {"state": "MI"} for i in range(70)};
    ready = json.dumps({"status": "READY", "points": [[42, -83], [41, -87]]});
    with patch.object(svc, "_by_id", return_value=places), patch.object(svc, "_route_cache", svc.OrderedDict()), patch.object(svc, "_last_route", -100.0), patch.object(svc.time, "monotonic", side_effect=list(range(100, 300, 2))), patch.object(svc, "_route_fetch", return_value=ready) {
        for i in range(1, 70) { _ = atlas_route("0", str(i)); }
        assert len(svc._route_cache) == 64;
    }
}

test "polygon checks catch foreign excursions even with inside endpoints" {
    ring = [[0, 0], [4, 0], [4, 4], [3, 4], [3, 1], [1, 1], [1, 4], [0, 4], [0, 0]];
    borders = [(ring[i], ring[i + 1]) for i in range(len(ring) - 1)];
    buckets = {i: borders for i in range(17)};
    with patch.object(svc, "_country", return_value=([[ring]], buckets)) {
        assert svc._us_route([[0.5, 0.5], [3.5, 0.5]]);
        assert not svc._us_route([[0.5, 2], [3.5, 2]]);
        assert not svc._us_route([[0.5, 0.5], [5, 5]]);
    }
}

test "wrong primitive argument types are rejected at runtime boundary" {
    bad = json.loads("42");
    assert json.loads(svc.interpret_response(bad as str, ""))["proposal"] is None;
    assert json.loads(svc.route_response(bad as str, "city"))["status"] == "ERROR";
}

test "incomplete mixed mode model proposal cannot erase intermediate cities" {
    proposal = svc._rules("San Francisco to New York then San Francisco", None);
    failed = False;
    try {
        svc._check_preserved("I flew from San Francisco to New York, drove to Boston and returned to San Francisco", None, proposal);
    } except ValueError { failed = True; }
    assert failed;
}

test "road geometry responses validate metrics and convert coordinate order" {
    start = {"lat": 42.0, "lon": -83.0};
    end = {"lat": 42.1, "lon": -83.1};
    payload = {"code": "Ok", "routes": [{"geometry": {"type": "LineString", "coordinates": [[-83.0, 42.0], [-83.1, 42.1]]}, "distance": 1234.0, "duration": 100.0}]};
    response = MagicMock();
    response.__enter__.return_value = response;
    response.read.return_value = json.dumps(payload).encode();
    with patch.object(svc.urllib.request, "urlopen", return_value=response), patch.object(svc, "_us_route", return_value=True) {
        result = json.loads(svc._route_fetch(start, end));
        assert result["status"] == "READY";
        assert result["points"][0] == [42.0, -83.0];
        assert result["distanceMeters"] == 1234.0;
        assert "not a record" in result["message"];
    }
    payload["routes"][0]["duration"] = -1.0;
    response.read.return_value = json.dumps(payload).encode();
    with patch.object(svc.urllib.request, "urlopen", return_value=response), patch.object(svc, "_us_route", return_value=True) {
        assert json.loads(svc._route_fetch(start, end))["status"] == "ERROR";
    }
}

test "network failure releases request lock and is briefly cached" {
    places = {"a": {"state": "MI"}, "b": {"state": "IL"}};
    with patch.object(svc, "_by_id", return_value=places), patch.object(svc, "_route_cache", svc.OrderedDict()), patch.object(svc, "_last_route", -100.0), patch.object(svc.time, "monotonic", return_value=100.0), patch.object(svc, "_route_fetch", side_effect=OSError("offline")) as provider {
        assert json.loads(atlas_route("a", "b"))["status"] == "ERROR";
        assert json.loads(atlas_route("a", "b"))["status"] == "ERROR";
        assert provider.call_count == 1;
        assert not svc._route_lock.locked();
    }
}

test "busy road request returns immediately without another network call" {
    places = {"a": {"state": "MI"}, "b": {"state": "IL"}};
    with svc._route_lock, patch.object(svc, "_by_id", return_value=places), patch.object(svc, "_route_fetch") as provider {
        result = json.loads(atlas_route("a", "b"));
        assert result["status"] == "ERROR" and "busy" in result["message"];
        provider.assert_not_called();
    }
}

test "oversized provider response is rejected before JSON parsing" {
    response = MagicMock();
    response.read.return_value = b"x" * 101;
    failed = False;
    try { _ = svc._read_json(response, 100); } except ValueError { failed = True; }
    assert failed;
}

test "empty new journey context is accepted for an initial request" {
    fresh = {"title": "", "status": "PLANNED", "stops": [], "legs": [], "note": "local only"};
    assert svc._context(json.dumps(fresh)) is None;
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}) {
        result = json.loads(atlas_interpret("Detroit to Chicago", json.dumps(fresh)));
        assert len(result["proposal"]["stops"]) == 2;
    }
    fresh["legs"] = [svc._blank_leg()];
    assert json.loads(atlas_interpret("Detroit to Chicago", json.dumps(fresh)))["proposal"] is None;
}

test "blank manual stop slots do not block explicit route interpretation" {
    selected = {"title": "Draft", "status": "PLANNED", "stops": [{"query": "", "place": None}], "legs": []};
    context = svc._context(json.dumps(selected));
    assert context["stops"] == [{"query": ""}];
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}) {
        result = json.loads(atlas_interpret("DTW -> JFK", json.dumps(selected)));
        assert result["source"] == "rules";
        assert [stop["query"] for stop in result["proposal"]["stops"]] == ["DTW", "JFK"];
    }
}

test "draft context preserves named queries and leg fields around blank slots" {
    selected = {"title": "Draft", "status": "PAST", "note": "PRIVATE",
        "stops": [{"query": "Detroit"}, {"query": "   "}, {"query": "Chicago"}],
        "legs": [svc._blank_leg("DRIVE"), svc._blank_leg("FLIGHT")]};
    selected["legs"][0]["departDate"] = "2026-10-12";
    selected["legs"][1]["timingNote"] = "evening departure";
    context = svc._context(json.dumps(selected));
    assert [stop["query"] for stop in context["stops"]] == ["Detroit", "", "Chicago"];
    assert context["legs"] == selected["legs"];
    assert context["status"] == "PAST";
    assert "PRIVATE" not in json.dumps(context);
    # A blank endpoint must not transfer a different leg's mode or dates.
    replaced = svc._rules("Detroit to Chicago", context);
    assert replaced["legs"][0] == svc._blank_leg();
    # Details that cannot safely be assigned to a new leg remain visible for review.
    assert "2026-10-12" in json.dumps(replaced["unresolved"]);
    assert "evening departure" in json.dumps(replaced["unresolved"]);
    assert "DRIVE" in json.dumps(replaced["unresolved"]);
}

test "mocked AI can fill a blank manual stop while output validation stays strict" {
    selected = {"title": "Draft", "status": "PLANNED", "stops": [{"query": ""}], "legs": []};
    proposal = svc._rules("DTW to JFK", None);
    payload = {"stop_reason": "end_turn", "content": [{"type": "text", "text": json.dumps(proposal)}]};
    response = MagicMock();
    response.__enter__.return_value = response;
    response.read.return_value = json.dumps(payload).encode();
    with patch.object(svc.urllib.request, "urlopen", return_value=response), patch.object(svc, "_ai_calls", svc.deque()), patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-only"}) {
        result = json.loads(atlas_interpret("DTW to JFK", json.dumps(selected)));
        assert result["source"] == "llm";
        assert len(result["proposal"]["stops"]) == 2;
    }
    failed = False;
    try { _ = svc._proposal(selected); } except ValueError { failed = True; }
    assert failed;
}

test "blank context does not exempt named stops or malformed values from validation" {
    selected = {"title": "Draft", "status": "PLANNED", "stops": [{"query": "Detroit"}, {"query": ""}], "legs": [svc._blank_leg()]};
    context = svc._context(json.dumps(selected));
    failed = False;
    try { svc._check_preserved("add Boston", context, svc._rules("Chicago to Boston", None)); } except ValueError { failed = True; }
    assert failed;
    malformed = json.loads(json.dumps(selected));
    for bad in [42, None, [], {}] {
        malformed["stops"][1]["query"] = bad;
        assert json.loads(atlas_interpret("Detroit to Boston", json.dumps(malformed)))["proposal"] is None;
    }
    selected["stops"][1]["query"] = "";
    selected["legs"] = [];
    assert json.loads(atlas_interpret("Detroit to Boston", json.dumps(selected)))["proposal"] is None;
}

test "repeating a route preserves all existing leg dates and modes" {
    current = svc._rules("Detroit to Chicago to Detroit to Chicago", None);
    current["legs"][0]["mode"] = "DRIVE";
    current["legs"][0]["departDate"] = "2026-01-01";
    current["legs"][1]["mode"] = "FLIGHT";
    current["legs"][2]["mode"] = "DRIVE";
    current["legs"][2]["departDate"] = "2026-02-01";
    result = svc._rules("Detroit to Chicago to Detroit to Chicago", current);
    assert result["legs"] == current["legs"];
    svc._check_preserved("same cities", current, result);
}

test "mode-only instead followup cannot erase existing cities" {
    current = svc._rules("Detroit to Chicago to Boston", None);
    proposal = svc._rules("Detroit to Chicago", None);
    failed = False;
    try { svc._check_preserved("Drive instead", current, proposal); } except ValueError { failed = True; }
    assert failed;
}

test "a complete mocked AI response keeps all stops and the original description" {
    proposal = svc._rules("Detroit to Chicago", None);
    payload = {"stop_reason": "end_turn", "content": [{"type": "text", "text": json.dumps(proposal)}]};
    response = MagicMock();
    response.__enter__.return_value = response;
    response.read.return_value = json.dumps(payload).encode();
    with patch.object(svc.urllib.request, "urlopen", return_value=response), patch.object(svc, "_ai_calls", svc.deque()), patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-only"}) {
        result = json.loads(atlas_interpret("Detroit to Chicago", ""));
        assert result["source"] == "llm";
        assert result["proposal"]["note"] == "Detroit to Chicago";
        assert len(result["proposal"]["stops"]) == 2;
    }
}

test "AI quota and malformed timing are enforced before use" {
    failed = False;
    with patch.object(svc, "_ai_calls", svc.deque([99.0])), patch.object(svc.time, "monotonic", return_value=100.0), patch.object(svc.urllib.request, "urlopen") as network {
        try { _ = svc._llm("Detroit to Chicago", None, "test-only"); } except ValueError { failed = True; }
        assert failed;
        network.assert_not_called();
    }
    leg = svc._blank_leg("DRIVE");
    leg["departDate"] = "2026-02-30";
    failed = False;
    try { _ = svc._leg(leg); } except ValueError { failed = True; }
    assert failed;
}

test "selected context accepts the manual editor field limits" {
    leg = svc._blank_leg("DRIVE");
    leg["timingNote"] = "n" * 2000;
    selected = {"title": "t" * 200, "status": "PLANNED", "stops": [{"query": "a" * 240}, {"query": "b" * 240}], "legs": [leg]};
    result = svc._context(json.dumps(selected));
    assert len(result["title"]) == 200;
    assert len(result["stops"][0]["query"]) == 240;
    assert len(result["legs"][0]["timingNote"]) == 2000;
}
