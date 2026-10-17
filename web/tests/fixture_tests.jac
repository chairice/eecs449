import os;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from server.models {
    ErrorCode, ProviderResult, RouteOption, SourceStatus, TimeKind, TravelMode,
    TripRequest, parse_timestamp, provider_result_to_json
}
import from server.providers.fixtures { DEFAULT_FIXTURE_PATH, FixtureRouteProvider, local_instant }
import from server.providers.route_provider { RouteProvider }

def fixture_request(local_date: str = "2026-10-23", local_time: str = "16:00", time_kind: TimeKind = TimeKind.DEPART_AFTER) -> TripRequest {
    return TripRequest(origin_text="Ann Arbor, MI", destination_text="Chicago, IL", local_date=local_date, local_time=local_time, time_kind=time_kind, max_price_cents=5000);
}

def available_routes(result: ProviderResult[list[RouteOption]]) -> list[RouteOption] {
    assert result.error is None;
    assert result.data is not None;
    return result.data;
}

test "normal fixture provides direct train bus and transfer with visible synthetic provenance" {
    provider: RouteProvider = FixtureRouteProvider();
    result = provider.search(fixture_request());
    routes = available_routes(result);
    assert result.metadata.status == SourceStatus.FIXTURE;
    assert len(routes) == 3;
    assert [option.transfers() for option in routes] == [0, 0, 1];
    assert [option.legs[0].mode for option in routes] == [TravelMode.TRAIN, TravelMode.BUS, TravelMode.TRAIN];
    assert [option.duration_minutes() for option in routes] == [320.0, 330.0, 360.0];
    for option in routes {
        assert option.source.status == SourceStatus.FIXTURE;
        assert option.price_cents is not None and option.price_cents <= 5000;
        assert parse_timestamp(option.legs[0].departure_at) >= parse_timestamp("2026-10-23T16:00:00-04:00");
        assert option.source.fetched_at is not None;
    }
    assert "SYNTHETIC_DATA" in [warning.code for warning in result.metadata.warnings];
    assert "NO_REALTIME_DATA" in [warning.code for warning in result.metadata.warnings];
    assert '"FIXTURE"' in provider_result_to_json(result);
}

test "repeated requests are deterministic and result mutation does not contaminate next search" {
    provider = FixtureRouteProvider();
    first = provider.search(fixture_request());
    baseline = provider_result_to_json(first);
    assert provider_result_to_json(provider.search(fixture_request())) == baseline;
    routes = available_routes(first);
    routes[0].price_cents = 1;
    first.metadata.warnings.clear();
    assert provider_result_to_json(provider.search(fixture_request())) == baseline;
}

test "unsupported corridor and reverse direction return successful empty search" {
    provider = FixtureRouteProvider();
    request = fixture_request();
    request.origin_text = "Detroit, MI";
    result = provider.search(request);
    assert available_routes(result) == [];
    assert result.metadata.status == SourceStatus.FIXTURE;
    request.origin_text = "Chicago";
    request.destination_text = "Ann Arbor";
    assert available_routes(provider.search(request)) == [];
    request.origin_text = "  ANN  ARBOR, Michigan ";
    request.destination_text = "Chicago Illinois";
    assert len(available_routes(provider.search(request))) == 3;
}

test "provider preserves candidates for planner filtering" {
    request = fixture_request(local_time="23:59");
    request.max_price_cents = 0;
    request.allowed_modes = [TravelMode.BUS];
    request.min_transfer_minutes = 999;
    assert len(available_routes(FixtureRouteProvider().search(request))) == 3;
}

test "future dates use each terminal timezone and correct seasonal offsets" {
    provider = FixtureRouteProvider();
    summer = available_routes(provider.search(fixture_request(local_date="2032-07-15")))[0];
    winter = available_routes(provider.search(fixture_request(local_date="2032-12-15")))[0];
    assert summer.legs[0].departure_at == "2032-07-15T17:20:00-04:00";
    assert summer.legs[0].arrival_at == "2032-07-15T21:40:00-05:00";
    assert winter.legs[0].departure_at == "2032-12-15T17:20:00-05:00";
    assert winter.legs[0].arrival_at == "2032-12-15T21:40:00-06:00";
    assert summer.duration_minutes() == winter.duration_minutes();
    arrival_request = fixture_request(local_date="2032-12-15", local_time="23:00", time_kind=TimeKind.ARRIVE_BY);
    assert available_routes(provider.search(arrival_request))[0].legs[-1].arrival_at.startswith("2032-12-15");
}

test "DST gaps and folds in requested local time require correction" {
    provider = FixtureRouteProvider();
    for (day, clock) in [("2026-03-08", "02:30"), ("2026-11-01", "01:30")] {
        for kind in [TimeKind.DEPART_AFTER, TimeKind.ARRIVE_BY] {
            result = provider.search(fixture_request(local_date=day, local_time=clock, time_kind=kind));
            assert result.data is None;
            assert result.error is not None;
            assert result.error.code == ErrorCode.INVALID_REQUEST;
            assert result.metadata.status == SourceStatus.UNAVAILABLE;
        }
    }
    assert local_instant("2026-10-23", "00:30", "America/Chicago", 1).isoformat() == "2026-10-24T00:30:00-05:00";
}

test "malformed fixture cannot become valid route data or live provenance" {
    original = Path(DEFAULT_FIXTURE_PATH).read_text(encoding="utf-8");
    malformed = ["{", "[]", original.replace('"FIXTURE"', '"LIVE"'), original.replace('"price_cents": 4500', '"price_cents": true'), original.replace('"origin_id": "ann-arbor"', '"origin_id": "missing"'), original.replace('"arrival_time": "21:40"', '"arrival_time": "12:00"'), original.replace('"mode": "TRAIN"', '"mode": "FLIGHT"'), original.replace('"id": "demo-direct-bus"', '"id": "demo-direct-train"')];
    with TemporaryDirectory() as temporary {
        path = Path(temporary) / "broken.json";
        for text in malformed {
            _ = path.write_text(text, encoding="utf-8");
            result = FixtureRouteProvider(fixture_path=str(path)).search(fixture_request());
            assert result.data is None;
            assert result.metadata.status == SourceStatus.UNAVAILABLE;
            assert result.error is not None;
            assert result.error.code == ErrorCode.PROVIDER_UNAVAILABLE;
            assert temporary not in result.error.message;
        }
    }
}

test "missing fixture is typed failure while valid empty fixture is successful" {
    with TemporaryDirectory() as temporary {
        path = Path(temporary) / "fixture.json";
        provider = FixtureRouteProvider(fixture_path=str(path));
        missing = provider.search(fixture_request());
        assert missing.error is not None and missing.error.code == ErrorCode.PROVIDER_UNAVAILABLE;
        _ = path.write_text('{"schema_version": 1, "synthetic": true, "source": {"provider": "empty-test", "status": "FIXTURE", "fetched_at": "2026-10-17T00:00:00Z"}, "places": [], "routes": []}', encoding="utf-8");
        result = provider.search(fixture_request());
        assert available_routes(result) == [];
        assert result.metadata.status == SourceStatus.FIXTURE;
    }
}

test "default fixture path works independently of current working directory" {
    previous = os.getcwd();
    with TemporaryDirectory() as temporary {
        try {
            os.chdir(temporary);
            assert len(available_routes(FixtureRouteProvider().search(fixture_request()))) == 3;
        } finally { os.chdir(previous); }
    }
}

test "representable local date overflow returns typed request or fixture failure" {
    request = fixture_request(local_date="9999-12-31", local_time="23:59");
    failed_request = FixtureRouteProvider().search(request);
    assert failed_request.error is not None;
    assert failed_request.error.code == ErrorCode.INVALID_REQUEST;
    assert failed_request.data is None;
    original = Path(DEFAULT_FIXTURE_PATH).read_text(encoding="utf-8");
    with TemporaryDirectory() as temporary {
        path = Path(temporary) / "overflow.json";
        _ = path.write_text(original.replace('"arrival_day_offset": 0', '"arrival_day_offset": 1'), encoding="utf-8");
        request.local_time = "12:00";
        failed_fixture = FixtureRouteProvider(fixture_path=str(path)).search(request);
        assert failed_fixture.error is not None;
        assert failed_fixture.error.code == ErrorCode.PROVIDER_UNAVAILABLE;
        assert failed_fixture.data is None;
    }
}
