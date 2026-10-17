import from server.models {
    ErrorCode, Place, PriorityPreset, ProviderMetadata, ReasonCode, RiskAssessment,
    RiskLevel, RouteLeg, RouteOption, ServiceStatus, SourceStatus, TimeKind,
    TravelMode, TripRequest, model_to_json
}
import from server.planner {
    ConstraintCode, preset_weights, rank_routes, transfer_slack
}

glob AS_OF: str = "2026-10-23T18:00:00Z";

def planning_request -> TripRequest {
    return TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-10-23", local_time="16:00", time_kind=TimeKind.DEPART_AFTER);
}
def start_place -> Place { return Place(id="a", name="Ann Arbor", latitude=42.28, longitude=-83.74, timezone="America/Detroit"); }
def middle_place -> Place { return Place(id="m", name="Interchange", latitude=42.29, longitude=-85.58, timezone="America/Detroit"); }
def end_place -> Place { return Place(id="c", name="Chicago", latitude=41.88, longitude=-87.64, timezone="America/Chicago"); }
def fresh_source -> ProviderMetadata {
    return ProviderMetadata(provider="planner-unit-test", status=SourceStatus.FIXTURE, fetched_at="2026-10-23T17:00:00Z", expires_at="2026-10-23T19:00:00Z");
}
def simple_route(route_id: str, departure: str = "2026-10-23T16:00:00-04:00", arrival: str = "2026-10-23T18:00:00-05:00", price: int | None = 4000) -> RouteOption {
    return RouteOption(id=route_id, legs=[RouteLeg(id=route_id + "-leg", mode=TravelMode.TRAIN, origin=start_place(), destination=end_place(), departure_at=departure, arrival_at=arrival, status=ServiceStatus.SCHEDULED, predicted_delay_minutes=0)], source=fresh_source(), price_cents=price);
}
def transfer_route(route_id: str, second_departure: str = "2026-10-23T17:50:00-04:00", with_walk: bool = True, arrival: str = "2026-10-23T19:00:00-05:00") -> RouteOption {
    legs = [RouteLeg(id=route_id + "-first", mode=TravelMode.TRAIN, origin=start_place(), destination=middle_place(), departure_at="2026-10-23T16:00:00-04:00", arrival_at="2026-10-23T17:00:00-04:00", predicted_delay_minutes=0)];
    if with_walk {
        legs.append(RouteLeg(id=route_id + "-walk", mode=TravelMode.WALK, origin=middle_place(), destination=middle_place(), departure_at="2026-10-23T17:00:00-04:00", arrival_at="2026-10-23T17:20:00-04:00"));
    }
    legs.append(RouteLeg(id=route_id + "-second", mode=TravelMode.BUS, origin=middle_place(), destination=end_place(), departure_at=second_departure, arrival_at=arrival, predicted_delay_minutes=0));
    return RouteOption(id=route_id, legs=legs, source=fresh_source(), price_cents=4000);
}
def known_risk(uncertainty: float = 0.0) -> RiskAssessment {
    return RiskAssessment(delay=RiskLevel.LOW, transfer=RiskLevel.LOW, weather=RiskLevel.LOW, uncertainty=uncertainty);
}

test "all presets have nonnegative normalized weights matching design priorities" {
    for preset in [PriorityPreset.BALANCED, PriorityPreset.FASTEST, PriorityPreset.LOWEST_COST, PriorityPreset.MOST_RELIABLE, PriorityPreset.FEWEST_TRANSFERS] {
        weights = preset_weights(preset);
        weights.validate();
        assert abs(weights.total() - 1.0) < 0.000001;
    }
    balanced = preset_weights(PriorityPreset.BALANCED);
    assert balanced.duration == 0.30 and balanced.reliability == 0.25 and balanced.price == 0.20 and balanced.transfers == 0.15 and balanced.weather == 0.10;
    assert preset_weights(PriorityPreset.FASTEST).duration == 0.55;
    assert preset_weights(PriorityPreset.LOWEST_COST).price == 0.50;
    assert preset_weights(PriorityPreset.MOST_RELIABLE).reliability == 0.45;
    assert preset_weights(PriorityPreset.FEWEST_TRANSFERS).transfers == 0.45;
}

test "preference preset changes speed price tradeoff reproducibly" {
    fast = simple_route("fast-expensive", arrival="2026-10-23T17:00:00-05:00", price=6000);
    cheap = simple_route("slow-cheap", arrival="2026-10-23T19:00:00-05:00", price=2000);
    request = planning_request();
    request.priority = PriorityPreset.FASTEST;
    assert rank_routes(request, [cheap, fast], AS_OF).routes[0].option.id == "fast-expensive";
    request.priority = PriorityPreset.LOWEST_COST;
    assert rank_routes(request, [fast, cheap], AS_OF).routes[0].option.id == "slow-cheap";
}

test "hard filtering happens before candidate relative normalization" {
    request = planning_request(); request.max_price_cents = 5000;
    first = simple_route("first", arrival="2026-10-23T17:00:00-05:00", price=4000);
    second = simple_route("second", arrival="2026-10-23T19:00:00-05:00", price=2000);
    extreme = simple_route("canceled-extreme", arrival="2026-10-23T15:10:00-05:00", price=1);
    extreme.legs[0].status = ServiceStatus.CANCELED;
    baseline = rank_routes(request, [first, second], AS_OF);
    added = rank_routes(request, [extreme, first, second], AS_OF);
    assert model_to_json(added.routes) == model_to_json(baseline.routes);
    assert added.rejected[0].route_id == "canceled-extreme";
    assert ConstraintCode.CANCELED in added.rejected[0].reasons;
}

test "hard budget distinguishes unknown free exactly at cap and over cap" {
    request = planning_request(); request.max_price_cents = 4000;
    result = rank_routes(request, [simple_route("unknown", price=None), simple_route("free", price=0), simple_route("exact", price=4000), simple_route("over", price=4001)], AS_OF);
    assert {route.option.id for route in result.routes} == {"free", "exact"};
    reasons = {item.route_id: item.reasons for item in result.rejected};
    assert reasons["unknown"] == [ConstraintCode.FARE_UNKNOWN];
    assert reasons["over"] == [ConstraintCode.OVER_BUDGET];
    request.max_price_cents = 0;
    result = rank_routes(request, [simple_route("free", price=0), simple_route("paid", price=1)], AS_OF);
    assert [route.option.id for route in result.routes] == ["free"];
}

test "canceled service and excluded transit modes remain hard constraints" {
    request = planning_request(); request.allowed_modes = [TravelMode.TRAIN];
    canceled = simple_route("canceled"); canceled.legs[0].status = ServiceStatus.CANCELED;
    bus = simple_route("bus"); bus.legs[0].mode = TravelMode.BUS;
    result = rank_routes(request, [canceled, bus, simple_route("train")], AS_OF);
    assert [route.option.id for route in result.routes] == ["train"];
    rejected = {item.route_id: item.reasons for item in result.rejected};
    assert ConstraintCode.CANCELED in rejected["canceled"];
    assert ConstraintCode.MODE_EXCLUDED in rejected["bus"];
}

test "walking consumes transfer slack without becoming a transit mode constraint" {
    request = planning_request(); request.allowed_modes = [TravelMode.TRAIN];
    enough = transfer_route("enough"); enough.legs[-1].mode = TravelMode.TRAIN;
    short = transfer_route("short", second_departure="2026-10-23T17:49:00-04:00"); short.legs[-1].mode = TravelMode.TRAIN;
    assert transfer_slack(enough) == [30.0];
    assert transfer_slack(short) == [29.0];
    result = rank_routes(request, [short, enough], AS_OF);
    assert [route.option.id for route in result.routes] == ["enough"];
    assert result.rejected[0].reasons == [ConstraintCode.TRANSFER_TOO_SHORT];
    assert ReasonCode.TIGHT_TRANSFER in result.routes[0].reason_codes;
    assert result.routes[0].option.transfers() == 1;
}

test "departure and arrival windows use terminal timezone and include exact boundary" {
    request = planning_request();
    exact = simple_route("exact");
    before = simple_route("before", departure="2026-10-23T15:59:59-04:00");
    tomorrow = simple_route("tomorrow", departure="2026-10-24T16:00:00-04:00", arrival="2026-10-24T18:00:00-05:00");
    result = rank_routes(request, [before, tomorrow, exact], AS_OF);
    assert [route.option.id for route in result.routes] == ["exact"];
    assert all(reason.reasons == [ConstraintCode.OUTSIDE_WINDOW] for reason in result.rejected);
    request.time_kind = TimeKind.ARRIVE_BY; request.local_time = "18:00";
    late = simple_route("late", arrival="2026-10-23T18:00:01-05:00");
    result = rank_routes(request, [late, exact], AS_OF);
    assert [route.option.id for route in result.routes] == ["exact"];
    assert result.routes[0].option.duration_minutes() == 180.0;
}

test "DST gap fold and maximum date overflow are typed invalid requests" {
    route = simple_route("route");
    for (day, clock) in [("2026-03-08", "02:30"), ("2026-11-01", "01:30"), ("9999-12-31", "23:59")] {
        request = planning_request(); request.local_date = day; request.local_time = clock;
        result = rank_routes(request, [route], AS_OF);
        assert result.error is not None;
        assert result.error.code == ErrorCode.INVALID_REQUEST;
        assert result.routes == [];
    }
}

test "empty and fully rejected searches return NO_ROUTES with rejection reasons" {
    empty = rank_routes(planning_request(), [], AS_OF);
    assert empty.error is not None and empty.error.code == ErrorCode.NO_ROUTES;
    assert empty.routes == [] and empty.rejected == [];
    canceled = simple_route("canceled"); canceled.legs[0].status = ServiceStatus.CANCELED;
    rejected = rank_routes(planning_request(), [canceled], AS_OF);
    assert rejected.error is not None and rejected.error.code == ErrorCode.NO_ROUTES;
    assert rejected.rejected[0].reasons == [ConstraintCode.CANCELED];
}

test "missing evidence has neutral utilities and uncertainty without false transfer claim" {
    route = simple_route("unknown", price=None); route.legs[0].predicted_delay_minutes = None;
    scored = rank_routes(planning_request(), [route], AS_OF).routes[0];
    assert scored.features.price == 0.5 and scored.features.reliability == 0.5 and scored.features.weather == 0.5;
    assert scored.risk.uncertainty == 0.75;
    assert scored.score == 65.0;
    assert ReasonCode.MISSING_DATA in scored.reason_codes;
    assert ReasonCode.LOWEST_COST not in scored.reason_codes;
    assert ReasonCode.TIGHT_TRANSFER not in scored.reason_codes;
    supplied = rank_routes(planning_request(), [route], AS_OF, {route.id: RiskAssessment()}).routes[0];
    assert ReasonCode.TIGHT_TRANSFER not in supplied.reason_codes;
    assert supplied.risk.uncertainty == 1.0;
}

test "stale zero-delay evidence is neutralized with explicit stale and unknown labels" {
    route = simple_route("route");
    fresh = rank_routes(planning_request(), [route], AS_OF, {route.id: known_risk()}).routes[0];
    stale = rank_routes(planning_request(), [route], "2026-10-23T19:00:00Z", {route.id: known_risk()}).routes[0];
    assert fresh.features.reliability == 1.0;
    assert stale.features.reliability == 0.5;
    assert stale.risk.delay == RiskLevel.UNKNOWN;
    assert stale.risk.uncertainty == 0.5;
    assert stale.score < fresh.score;
    assert ReasonCode.STALE_DATA in stale.reason_codes and ReasonCode.MISSING_DATA in stale.reason_codes;
}

test "missing delay on one leg never erases high risk already observed on another" {
    route = transfer_route("connection");
    route.legs[0].predicted_delay_minutes = 60;
    complete = rank_routes(planning_request(), [route], AS_OF).routes[0];
    route.legs[-1].predicted_delay_minutes = None;
    partial = rank_routes(planning_request(), [route], AS_OF).routes[0];
    assert complete.features.reliability == 0.0 and partial.features.reliability == 0.0;
    assert partial.risk.delay == RiskLevel.HIGH;
    assert partial.risk.uncertainty > complete.risk.uncertainty;
    assert partial.score < complete.score;
    assert ReasonCode.DELAY_RISK_HIGH in partial.reason_codes;
}

test "same inputs preserve inputs and produce identical ranking regardless of candidate order" {
    request = planning_request(); first = simple_route("b"); second = simple_route("a");
    before = model_to_json([first, second]);
    risk = known_risk(); risk.reason_codes = [ReasonCode.FASTEST];
    risk_before = model_to_json(risk);
    ranked = rank_routes(request, [first, second], AS_OF, {"a": risk, "b": risk});
    reversed = rank_routes(request, [second, first], AS_OF, {"a": risk, "b": risk});
    assert [item.option.id for item in ranked.routes] == ["a", "b"];
    assert model_to_json(ranked.routes) == model_to_json(reversed.routes);
    assert model_to_json([first, second]) == before;
    assert model_to_json(risk) == risk_before;
    assert ranked.routes[0].reason_codes.count(ReasonCode.FASTEST) == 1;
}

test "equal scores break ties by fewer transfers then earlier arrival" {
    direct = simple_route("z-direct");
    connection = transfer_route("a-connection", second_departure="2026-10-23T17:30:00-04:00", with_walk=False, arrival="2026-10-23T18:00:00-05:00");
    result = rank_routes(planning_request(), [connection, direct], AS_OF, {direct.id: known_risk(0.75), connection.id: known_risk()});
    assert result.routes[0].score == result.routes[1].score;
    assert result.routes[0].option.id == "z-direct";
    earlier = simple_route("z-earlier");
    later = simple_route("a-later", departure="2026-10-23T17:00:00-04:00", arrival="2026-10-23T19:00:00-05:00");
    result = rank_routes(planning_request(), [later, earlier], AS_OF);
    assert result.routes[0].score == result.routes[1].score;
    assert result.routes[0].option.id == "z-earlier";
}

test "equal scores transfers and arrival break tie by lower price before route ID" {
    cheap = simple_route("z-cheap", arrival="2026-10-23T19:00:00-05:00", price=2000);
    fast = simple_route("a-fast", departure="2026-10-23T17:00:00-04:00", arrival="2026-10-23T19:00:00-05:00", price=4000);
    result = rank_routes(planning_request(), [fast, cheap], AS_OF, {fast.id: known_risk(1.0), cheap.id: known_risk()});
    assert result.routes[0].score == result.routes[1].score;
    assert result.routes[0].option.id == "z-cheap";
}

test "malformed risk duplicate IDs invalid as-of and mutated requests return typed errors" {
    route = simple_route("route"); risk = known_risk(); risk.uncertainty = 2.0;
    invalid_risk = rank_routes(planning_request(), [route], AS_OF, {route.id: risk});
    assert invalid_risk.error is not None and invalid_risk.error.code == ErrorCode.INVALID_REQUEST;
    duplicate = rank_routes(planning_request(), [route, route], AS_OF);
    assert duplicate.error is not None and duplicate.error.code == ErrorCode.INVALID_REQUEST;
    bad_clock = rank_routes(planning_request(), [route], "2026-10-23T18:00:00");
    assert bad_clock.error is not None and bad_clock.error.code == ErrorCode.INVALID_REQUEST;
    request = planning_request(); request.min_transfer_minutes = -1;
    bad_request = rank_routes(request, [route], AS_OF);
    assert bad_request.error is not None and bad_request.error.code == ErrorCode.INVALID_REQUEST;
}

test "delay thresholds and supplied weather risk affect utility with grounded reason codes" {
    request = planning_request();
    for (delay, expected) in [(0, RiskLevel.LOW), (14, RiskLevel.LOW), (15, RiskLevel.MODERATE), (29, RiskLevel.MODERATE), (30, RiskLevel.HIGH), (120, RiskLevel.HIGH)] {
        route = simple_route("threshold"); route.legs[0].predicted_delay_minutes = delay;
        scored = rank_routes(request, [route], AS_OF).routes[0];
        assert scored.risk.delay == expected;
        assert scored.option.legs[0].predicted_delay_minutes == delay;
        assert (ReasonCode.DELAY_RISK_HIGH in scored.reason_codes) == (expected == RiskLevel.HIGH);
    }
    route = simple_route("weather");
    safe = known_risk(); severe = known_risk(); severe.weather = RiskLevel.HIGH;
    safe_result = rank_routes(request, [route], AS_OF, {route.id: safe}).routes[0];
    severe_result = rank_routes(request, [route], AS_OF, {route.id: severe}).routes[0];
    assert safe_result.features.weather == 1.0 and severe_result.features.weather == 0.0;
    assert safe_result.score - severe_result.score == 10.0;
    assert ReasonCode.WEATHER_RISK_HIGH in severe_result.reason_codes;
}

test "transfer buffer threshold affects utility as well as warning" {
    tight = transfer_route("tight", second_departure="2026-10-23T17:50:00-04:00");
    comfortable = transfer_route("comfortable", second_departure="2026-10-23T18:05:00-04:00");
    result = rank_routes(planning_request(), [tight, comfortable], AS_OF);
    assert [item.option.id for item in result.routes] == ["comfortable", "tight"];
    assert result.routes[0].features.transfers == 0.5;
    assert result.routes[1].features.transfers == 0.25;
    assert result.routes[0].score - result.routes[1].score == 3.75;
    assert ReasonCode.TIGHT_TRANSFER not in result.routes[0].reason_codes;
    assert ReasonCode.TIGHT_TRANSFER in result.routes[1].reason_codes;
}
