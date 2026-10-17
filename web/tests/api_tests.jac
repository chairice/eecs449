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
