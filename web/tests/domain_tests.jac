import json;
import from server.models {
    DomainError, ErrorCode, Place, PriorityPreset, ProviderMetadata, ProviderResult,
    RiskAssessment, RiskLevel, RouteLeg, RouteOption, ScoreDimensions, ScoredRoute,
    ServiceStatus, SourceStatus, TimeKind, TravelMode, TripPlan, TripPlanDraft,
    TripIntent, TripRequest, UserPreferences, WeatherEvidence, model_to_json, parse_timestamp,
    provider_result_to_json, route_option_from_json, trip_request_from_json
}

def request_fixture -> TripRequest {
    return TripRequest(origin_text="Ann Arbor, MI", destination_text="Chicago, IL", local_date="2026-10-23", local_time="16:00", time_kind=TimeKind.DEPART_AFTER, max_price_cents=5000);
}
def source_fixture -> ProviderMetadata {
    return ProviderMetadata(provider="corridor-fixture-v1", status=SourceStatus.FIXTURE, fetched_at="2026-10-16T18:00:00Z", expires_at="2026-10-24T00:00:00Z");
}
def origin_fixture -> Place {
    return Place(id="arb", name="Ann Arbor", latitude=42.2814, longitude=-83.7483, timezone="America/Detroit");
}
def destination_fixture -> Place {
    return Place(id="chi", name="Chicago Union Station", latitude=41.8786, longitude=-87.6405, timezone="America/Chicago");
}
def route_fixture -> RouteOption {
    return RouteOption(id="train-355", legs=[RouteLeg(id="train-leg", mode=TravelMode.TRAIN, origin=origin_fixture(), destination=destination_fixture(), departure_at="2026-10-23T16:00:00-04:00", arrival_at="2026-10-23T19:00:00-05:00", operator="Amtrak", service="355", status=ServiceStatus.SCHEDULED)], source=source_fixture(), price_cents=4500);
}
def score_fixture -> ScoredRoute {
    return ScoredRoute(option=route_fixture(), risk=RiskAssessment(), features=ScoreDimensions(duration=0.5, reliability=0.5, price=0.5, transfers=1.0, weather=0.5), score=47.5);
}
def weights_fixture -> ScoreDimensions {
    return ScoreDimensions(duration=0.30, reliability=0.25, price=0.20, transfers=0.15, weather=0.10);
}

test "request JSON roundtrip keeps cents enum strings and null semantics" {
    original = request_fixture();
    encoded = model_to_json(original);
    assert '"DEPART_AFTER"' in encoded;
    assert '"max_price_cents": 5000' in encoded;
    assert "__jac" not in encoded;
    restored = trip_request_from_json(encoded);
    assert model_to_json(restored) == encoded;
    assert restored.time_kind == TimeKind.DEPART_AFTER;
    assert restored.allowed_modes == [TravelMode.TRAIN, TravelMode.BUS];
}

test "route roundtrip preserves typed nested objects and provenance" {
    original = route_fixture();
    restored = route_option_from_json(model_to_json(original));
    assert model_to_json(restored) == model_to_json(original);
    assert restored.source.status == SourceStatus.FIXTURE;
    assert restored.legs[0].origin.timezone == "America/Detroit";
    assert restored.duration_minutes() == 240.0;
    assert restored.transfers() == 0;
}

test "unknown price is distinct from a free route" {
    route = route_fixture();
    route.price_cents = None;
    assert route_option_from_json(model_to_json(route)).price_cents is None;
    route.price_cents = 0;
    assert route_option_from_json(model_to_json(route)).price_cents == 0;
}

test "strict JSON input rejects wrong types unknown keys and enums" {
    valid = model_to_json(request_fixture());
    for replacement in ["true", "50.5", "\"5000\"", "-1"] {
        with testraises(ValueError) { _ = trip_request_from_json(valid.replace('"max_price_cents": 5000', '"max_price_cents": ' + replacement)); }
    }
    with testraises(ValueError) { _ = trip_request_from_json(valid.replace('"max_price_cents"', '"max_prize_cents"')); }
    with testraises(ValueError) { _ = trip_request_from_json(valid.replace('"TRAIN"', '"FLIGHT"')); }
    with testraises(ValueError) { _ = trip_request_from_json("[]"); }
    with testraises(ValueError) { _ = trip_request_from_json("{}"); }
}

test "request validates dates times places and transit modes" {
    valid = model_to_json(request_fixture());
    for (old, replacement) in [("2026-10-23", "2026-02-30"), ("16:00", "25:00"), ("16:00", "4:00"), ("Ann Arbor, MI", "  "), ("Chicago, IL", "Ann Arbor, MI"), ("TRAIN", "WALK")] {
        with testraises(ValueError) { _ = trip_request_from_json(valid.replace(old, replacement)); }
    }
    with testraises(ValueError) {
        _ = TripRequest(origin_text="A", destination_text="B", local_date="2026-10-23", local_time="16:00", time_kind=TimeKind.DEPART_AFTER, allowed_modes=[]);
    }
}

test "timestamps require offset and compare actual instants" {
    with testraises(ValueError) { _ = parse_timestamp("2026-10-23T16:00:00"); }
    with testraises(ValueError) { _ = parse_timestamp("2026-10-23"); }
    assert parse_timestamp("2026-10-23T16:00:00-04:00") == parse_timestamp("2026-10-23T20:00:00Z");
    # Fall-back crosses the repeated local hour: elapsed time is two hours.
    route = route_fixture();
    route.legs[0].departure_at = "2026-11-01T01:30:00-04:00";
    route.legs[0].arrival_at = "2026-11-01T02:30:00-05:00";
    assert route.duration_minutes() == 120.0;
}

test "route rejects reversed disconnected overlapping and empty legs" {
    route = route_fixture();
    with testraises(ValueError) { _ = RouteOption(id="empty", legs=[], source=source_fixture()); }
    with testraises(ValueError) {
        _ = RouteLeg(id="bad", mode=TravelMode.TRAIN, origin=origin_fixture(), destination=destination_fixture(), departure_at="2026-10-23T16:00:00-04:00", arrival_at="2026-10-23T14:59:00-05:00");
    }
    second = RouteLeg(id="second", mode=TravelMode.BUS, origin=origin_fixture(), destination=destination_fixture(), departure_at="2026-10-23T20:00:00-05:00", arrival_at="2026-10-23T22:00:00-05:00");
    with testraises(ValueError) { _ = RouteOption(id="disconnected", legs=[route.legs[0], second], source=source_fixture()); }
    second.origin = destination_fixture();
    second.departure_at = "2026-10-23T18:59:00-05:00";
    with testraises(ValueError) { _ = RouteOption(id="overlap", legs=[route.legs[0], second], source=source_fixture()); }
}

test "walking connectors do not count as additional vehicle transfers" {
    first = route_fixture().legs[0];
    walk = RouteLeg(id="walk", mode=TravelMode.WALK, origin=destination_fixture(), destination=destination_fixture(), departure_at="2026-10-23T19:00:00-05:00", arrival_at="2026-10-23T19:10:00-05:00");
    bus = RouteLeg(id="bus", mode=TravelMode.BUS, origin=destination_fixture(), destination=destination_fixture(), departure_at="2026-10-23T19:30:00-05:00", arrival_at="2026-10-23T20:00:00-05:00");
    option = RouteOption(id="connection", legs=[first, walk, bus], source=source_fixture());
    assert option.transfers() == 1;
    assert option.duration_minutes() == 300.0;
}

test "provider envelopes distinguish successful empty search from outage" {
    result: ProviderResult[list[RouteOption]] = ProviderResult(metadata=source_fixture(), data=[]);
    assert result.data == [];
    assert json.loads(provider_result_to_json(result))["data"] == [];
    unavailable = ProviderMetadata(provider="nws", status=SourceStatus.UNAVAILABLE);
    error = DomainError(code=ErrorCode.PROVIDER_UNAVAILABLE, message="Forecast unavailable", retryable=True);
    failed: ProviderResult[list[RouteOption]] = ProviderResult(metadata=unavailable, error=error);
    assert failed.data is None;
    assert json.loads(provider_result_to_json(failed))["error"]["code"] == "PROVIDER_UNAVAILABLE";
    with testraises(ValueError) { _ = ProviderResult(metadata=source_fixture()); }
    with testraises(ValueError) { _ = ProviderResult(metadata=unavailable, data=[route_fixture()], error=error); }
    with testraises(ValueError) { _ = ProviderMetadata(provider="nws", status=SourceStatus.LIVE); }
    with testraises(ValueError) { _ = ProviderMetadata(provider="nws", status=SourceStatus.CACHED, fetched_at="2026-10-16T18:00:00Z", expires_at="2026-10-16T17:59:00Z"); }
}

test "weather and score dimensions reject impossible and nonfinite values" {
    for probability in [-0.1, 1.1, float("nan"), float("inf")] {
        with testraises(ValueError) {
            _ = WeatherEvidence(place=origin_fixture(), valid_from="2026-10-23T16:00:00-04:00", valid_until="2026-10-23T17:00:00-04:00", source=source_fixture(), precipitation_probability=probability);
        }
        with testraises(ValueError) { _ = ScoreDimensions(duration=probability, reliability=0.5, price=0.5, transfers=0.5, weather=0.5); }
    }
    with testraises(ValueError) { _ = RiskAssessment(uncertainty=-0.1); }
    with testraises(ValueError) { _ = Place(id="bad", name="Bad", latitude=91.0, longitude=0.0, timezone="UTC"); }
    with testraises(ValueError) {
        _ = WeatherEvidence(place=origin_fixture(), valid_from="2026-10-23T16:00:00-04:00", valid_until="2026-10-23T17:00:00-04:00", source=ProviderMetadata(provider="nws", status=SourceStatus.UNAVAILABLE), alert_severity=RiskLevel.LOW);
    }
}

test "draft validates recommendation expiry and reproducible weight set" {
    route = score_fixture();
    valid = TripPlanDraft(id="draft-1", request=request_fixture(), routes=[route], recommended_route_id=route.option.id, weights=weights_fixture(), created_at="2026-10-16T18:00:00Z", expires_at="2026-10-16T18:30:00Z");
    assert json.loads(model_to_json(valid))["routes"][0]["option"]["source"]["status"] == "FIXTURE";
    with testraises(ValueError) { _ = TripPlanDraft(id="draft-1", request=request_fixture(), routes=[route], recommended_route_id="missing", weights=weights_fixture(), created_at=valid.created_at, expires_at=valid.expires_at); }
    with testraises(ValueError) { _ = TripPlanDraft(id="draft-1", request=request_fixture(), routes=[route, route], recommended_route_id=route.option.id, weights=weights_fixture(), created_at=valid.created_at, expires_at=valid.expires_at); }
    with testraises(ValueError) { _ = TripPlanDraft(id="draft-1", request=request_fixture(), routes=[route], recommended_route_id=route.option.id, weights=weights_fixture(), created_at=valid.created_at, expires_at=valid.created_at); }
    weights = weights_fixture(); weights.price = 0.3;
    with testraises(ValueError) { _ = TripPlanDraft(id="draft-1", request=request_fixture(), routes=[route], recommended_route_id=route.option.id, weights=weights, created_at=valid.created_at, expires_at=valid.expires_at); }
}

test "plans require an owner and distinct backup while preferences are independent" {
    route = score_fixture();
    with testraises(ValueError) { _ = TripPlan(id="plan-1", owner_id="", request=request_fixture(), selected_route=route, created_at="2026-10-16T18:00:00Z"); }
    with testraises(ValueError) { _ = TripPlan(id="plan-1", owner_id="owner-1", request=request_fixture(), selected_route=route, backup_route=route, created_at="2026-10-16T18:00:00Z"); }
    first = UserPreferences(priority=PriorityPreset.FASTEST);
    second = UserPreferences();
    first.avoided_modes.append(TravelMode.BUS);
    assert second.avoided_modes == [];
    assert second.priority == PriorityPreset.BALANCED;
    with testraises(ValueError) { _ = UserPreferences(min_transfer_minutes=-1); }
}

test "partial intent remains incomplete without accepting malformed supplied fields" {
    intent = TripIntent(origin_text="Ann Arbor");
    assert intent.destination_text is None;
    assert json.loads(model_to_json(intent))["local_date"] is None;
    with testraises(ValueError) { _ = TripIntent(max_price_cents=-1); }
    with testraises(ValueError) { _ = TripIntent(local_date="2026-02-30"); }
    with testraises(ValueError) { _ = TripIntent(local_time="25:00"); }
    with testraises(ValueError) { _ = TripIntent(allowed_modes=[TravelMode.WALK]); }
}

test "boolean numerics are rejected by direct model constructors" {
    with testraises(ValueError) { _ = ScoreDimensions(duration=True, reliability=0.5, price=0.5, transfers=0.5, weather=0.5); }
    with testraises(ValueError) { _ = Place(id="bad", name="Bad", latitude=True, longitude=0.0, timezone="UTC"); }
    with testraises(ValueError) { _ = UserPreferences(max_price_cents=True); }
    with testraises(ValueError) { _ = RiskAssessment(uncertainty=True); }
    with testraises(ValueError) { _ = ScoredRoute(option=route_fixture(), risk=RiskAssessment(), features=weights_fixture(), score=True); }
    with testraises(ValueError) {
        _ = WeatherEvidence(place=origin_fixture(), valid_from="2026-10-23T16:00:00-04:00", valid_until="2026-10-23T17:00:00-04:00", source=source_fixture(), wind_kph=True);
    }
}
