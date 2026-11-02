import json;
import from datetime { datetime, timezone }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.testing.testing { JacTestClient }
import from server.api { MAX_REQUEST_BYTES, _plan_response, plan_trip }
import from server.models { TimeKind, TripRequest, model_to_json, parse_timestamp }
import from server.providers.fixtures { FixtureRouteProvider }

glob AS_OF: str = "2026-10-23T18:00:00Z";

def _request_payload -> str {
    return model_to_json(TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-10-23", local_time="16:00", time_kind=TimeKind.DEPART_AFTER, max_price_cents=5000));
}

test "a return search plans Chicago to Ann Arbor any time on the return date" {
    payload = model_to_json(TripRequest(origin_text="Chicago, IL", destination_text="Ann Arbor, MI", local_date="2026-10-30", local_time="00:00", time_kind=TimeKind.DEPART_AFTER, max_price_cents=5000));
    result = json.loads(_plan_response(payload, FixtureRouteProvider(), AS_OF));
    assert result["error"] is None and len(result["routes"]) == 3;
    for route in result["routes"] {
        legs = route["option"]["legs"];
        assert legs[0]["origin"]["id"] == "chicago" and legs[-1]["destination"]["id"] == "ann-arbor";
        assert legs[0]["departure_at"].startswith("2026-10-30");
    }
}

test "planning response preserves explicit canonical wire contract and fixture provenance" {
    payload = _request_payload();
    encoded = _plan_response(payload, FixtureRouteProvider(), AS_OF);
    result = json.loads(encoded);
    assert set(result) == {"schema_version", "mode", "request", "as_of", "routes", "rejected", "weights", "sources", "error"};
    assert result["schema_version"] == 1 and result["mode"] == "FIXTURE";
    assert result["error"] is None and len(result["routes"]) == 3;
    assert result["request"] == json.loads(payload);
    assert result["as_of"] == AS_OF;
    assert result["sources"][0]["status"] == "FIXTURE";
    assert "SYNTHETIC_DATA" in [warning["code"] for warning in result["sources"][0]["warnings"]];
    assert all(route["option"]["source"]["status"] == "FIXTURE" for route in result["routes"]);
    assert all(route["risk"]["weather"] == "UNKNOWN" for route in result["routes"]);
    assert [route["score"] for route in result["routes"]] == sorted([route["score"] for route in result["routes"]], reverse=True);
    assert "draft_id" not in encoded and "owner_id" not in encoded and "_jac" not in encoded;
    assert _plan_response(payload, FixtureRouteProvider(), AS_OF) == encoded;
}

test "invalid JSON fields numeric types and oversized UTF8 input return sanitized typed errors" {
    valid = _request_payload();
    invalid = ["{", "[]", "{}", valid.replace('"max_price_cents": 5000', '"max_price_cents": true'), valid.replace('"origin_text"', '"private-secret-field"'), " " * (MAX_REQUEST_BYTES + 1), "é" * (MAX_REQUEST_BYTES // 2 + 1), "[" * 2000];
    for payload in invalid {
        result = json.loads(_plan_response(payload, FixtureRouteProvider(), AS_OF));
        assert result["error"]["code"] == "INVALID_REQUEST";
        assert result["routes"] == [] and result["sources"] == [] and result["request"] is None;
        assert "private-secret-field" not in result["error"]["message"];
    }
}

test "no feasible routes retain constraint reasons while unsupported corridor is successful provider empty" {
    late = _request_payload().replace('"16:00"', '"23:59"');
    result = json.loads(_plan_response(late, FixtureRouteProvider(), AS_OF));
    assert result["error"]["code"] == "NO_ROUTES" and result["routes"] == [];
    assert len(result["rejected"]) == 3;
    assert all("OUTSIDE_WINDOW" in item["reasons"] for item in result["rejected"]);
    assert result["sources"][0]["status"] == "FIXTURE";
    other = json.loads(_plan_response(_request_payload().replace("Ann Arbor", "Detroit"), FixtureRouteProvider(), AS_OF));
    assert other["error"]["code"] == "NO_ROUTES" and other["rejected"] == [];
    assert other["sources"][0]["status"] == "FIXTURE";
}

test "missing fixture returns outage instead of no routes and hides local paths" {
    with TemporaryDirectory() as temporary {
        provider = FixtureRouteProvider(fixture_path=str(Path(temporary) / "missing.json"));
        encoded = _plan_response(_request_payload(), provider, AS_OF);
        result = json.loads(encoded);
        assert result["error"]["code"] == "PROVIDER_UNAVAILABLE";
        assert result["sources"][0]["status"] == "UNAVAILABLE";
        assert result["routes"] == [] and result["rejected"] == [];
        assert temporary not in encoded;
    }
}

test "DST and calendar overflow remain typed invalid request responses" {
    for (day, clock) in [("2026-03-08", "02:30"), ("2026-11-01", "01:30"), ("9999-12-31", "23:59")] {
        payload = _request_payload().replace("2026-10-23", day).replace("16:00", clock);
        result = json.loads(_plan_response(payload, FixtureRouteProvider(), AS_OF));
        assert result["error"]["code"] == "INVALID_REQUEST";
        assert result["routes"] == [];
    }
}

test "public function obtains its as-of timestamp from the server clock" {
    before = datetime.now(timezone.utc);
    result = json.loads(plan_trip(_request_payload()));
    after = datetime.now(timezone.utc);
    assert before <= parse_timestamp(result["as_of"]) <= after;
    assert result["error"] is None;
}

test "main entry registers anonymous planning endpoint and hides internal helpers" {
    api_path = str(Path(__file__).resolve().parents[1] / "main.jac");
    with TemporaryDirectory() as temporary {
        client = JacTestClient.from_file(api_path, base_path=temporary);
        try {
            response = client.post("/function/plan_trip", json={"request_json": _request_payload()});
            assert response.status_code == 200;
            envelope = response.json();
            assert envelope["ok"] is True;
            result = json.loads(envelope["data"]["result"]);
            assert result["error"] is None and result["mode"] == "FIXTURE";
            assert len(result["routes"]) == 3;
            invalid = client.post("/function/plan_trip", json={"request_json": "{"});
            assert invalid.status_code == 200;
            assert json.loads(invalid.json()["data"]["result"])["error"]["code"] == "INVALID_REQUEST";
            helper = client.post("/function/_plan_response", json={});
            assert helper.status_code in [404, 405];
        } finally { client.close(); }
    }
}

test "an arrive-by search covers every day from the search to the deadline" {
    payload = model_to_json(TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-11-05", local_time="23:00", time_kind=TimeKind.ARRIVE_BY));
    # Monday 5 PM in Ann Arbor: that day's 4:30 PM connection has already left.
    as_of = "2026-11-02T22:00:00Z";
    result = json.loads(_plan_response(payload, FixtureRouteProvider(), as_of));
    routes = result["routes"];
    days = sorted(set(route["option"]["legs"][0]["departure_at"][:10] for route in routes));
    assert result["error"] is None and days == ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05"];
    assert len(routes) == 11 and len(set(route["option"]["id"] for route in routes)) == 11;
    assert all(parse_timestamp(route["option"]["legs"][0]["departure_at"]) >= parse_timestamp(as_of) for route in routes);
    assert all(parse_timestamp(route["option"]["legs"][-1]["arrival_at"]) <= parse_timestamp("2026-11-05T23:00:00-06:00") for route in routes);
    # Equal options lean toward the deadline day.
    assert routes[0]["option"]["legs"][0]["departure_at"].startswith("2026-11-05");
    leave = json.loads(_plan_response(payload.replace("ARRIVE_BY", "DEPART_AFTER").replace('"23:00"', '"16:00"'), FixtureRouteProvider(), as_of));
    assert len(leave["routes"]) == 3;
}

test "an arrive-by window reaches back at most a week" {
    payload = model_to_json(TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-11-20", local_time="23:00", time_kind=TimeKind.ARRIVE_BY));
    result = json.loads(_plan_response(payload, FixtureRouteProvider(), "2026-11-02T14:00:00Z"));
    days = sorted(set(route["option"]["legs"][0]["departure_at"][:10] for route in result["routes"]));
    assert days[0] == "2026-11-13" and days[-1] == "2026-11-20" and len(days) == 8;
}
