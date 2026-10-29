"""
Pure feasibility filtering and ranking. All time/evidence inputs are explicit."""

import from datetime { datetime, timezone }
import from zoneinfo { ZoneInfo }
import from server.models {
    TripRequest, RouteOption, ScoredRoute, ScoreDimensions, RiskAssessment,
    PriorityPreset, TravelMode, TimeKind, ServiceStatus, RiskLevel, ReasonCode,
    DomainError, ErrorCode, parse_timestamp, model_to_json
}

enum ConstraintCode: str {
    CANCELED = "CANCELED", MODE_EXCLUDED = "MODE_EXCLUDED",
    OUTSIDE_WINDOW = "OUTSIDE_WINDOW", OVER_BUDGET = "OVER_BUDGET",
    FARE_UNKNOWN = "FARE_UNKNOWN", TRANSFER_TOO_SHORT = "TRANSFER_TOO_SHORT"
}

obj RejectedRoute {
    has route_id: str, reasons: list[ConstraintCode];
}

obj RankingResult {
    has routes: list[ScoredRoute], rejected: list[RejectedRoute], weights: ScoreDimensions;
    has error: DomainError | None = None;
}

def preset_weights(preset: PriorityPreset) -> ScoreDimensions {
    if preset == PriorityPreset.FASTEST { return ScoreDimensions(0.55, 0.15, 0.10, 0.10, 0.10); }
    if preset == PriorityPreset.LOWEST_COST { return ScoreDimensions(0.15, 0.15, 0.50, 0.10, 0.10); }
    if preset == PriorityPreset.MOST_RELIABLE { return ScoreDimensions(0.15, 0.45, 0.10, 0.20, 0.10); }
    if preset == PriorityPreset.FEWEST_TRANSFERS { return ScoreDimensions(0.15, 0.20, 0.10, 0.45, 0.10); }
    if preset != PriorityPreset.BALANCED { raise ValueError("unknown priority preset"); }
    return ScoreDimensions(0.30, 0.25, 0.20, 0.15, 0.10);
}

"""Reject nonexistent/ambiguous wall times rather than guessing across DST."""
def request_instant(request: TripRequest, zone_name: str) -> datetime {
    wall = datetime.fromisoformat(request.local_date + "T" + request.local_time);
    zone = ZoneInfo(zone_name);
    first = wall.replace(tzinfo=zone, fold=0);
    second = wall.replace(tzinfo=zone, fold=1);
    first_valid = first.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) == wall;
    second_valid = second.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) == wall;
    if not first_valid and not second_valid { raise ValueError("requested local time does not exist; choose another time"); }
    if first_valid and second_valid and first.utcoffset() != second.utcoffset() { raise ValueError("requested local time is ambiguous; choose an unambiguous time"); }
    return first if first_valid else second;
}


"""Slack excludes walking time between vehicles; walking is not a transfer."""
def transfer_slack(route: RouteOption) -> list[float] {
    result: list[float] = [];
    previous = -1;
    walking = 0.0;
    for i in range(len(route.legs)) {
        leg = route.legs[i];
        if leg.mode == TravelMode.WALK {
            if previous >= 0 { walking += (parse_timestamp(leg.arrival_at) - parse_timestamp(leg.departure_at)).total_seconds() / 60.0; }
        } else {
            if previous >= 0 {
                total = (parse_timestamp(leg.departure_at) - parse_timestamp(route.legs[previous].arrival_at)).total_seconds() / 60.0;
                result.append(total - walking);
            }
            previous = i;
            walking = 0.0;
        }
    }
    return result;
}

def rejection_reasons(request: TripRequest, route: RouteOption) -> list[ConstraintCode] {
    reasons: list[ConstraintCode] = [];
    if `any([leg.status == ServiceStatus.CANCELED for leg in route.legs]) { reasons.append(ConstraintCode.CANCELED); }
    if `any([leg.mode != TravelMode.WALK and leg.mode not in request.allowed_modes for leg in route.legs]) { reasons.append(ConstraintCode.MODE_EXCLUDED); }
    cap = request.max_price_cents;
    price = route.price_cents;
    if cap is not None {
        if price is None { reasons.append(ConstraintCode.FARE_UNKNOWN); }
        elif price > cap { reasons.append(ConstraintCode.OVER_BUDGET); }
    }
    if `any([slack < request.min_transfer_minutes for slack in transfer_slack(route)]) { reasons.append(ConstraintCode.TRANSFER_TOO_SHORT); }
    if request.time_kind == TimeKind.DEPART_AFTER {
        zone = route.legs[0].origin.timezone;
        instant = parse_timestamp(route.legs[0].departure_at);
        outside = instant < request_instant(request, zone);
    } else {
        zone = route.legs[-1].destination.timezone;
        instant = parse_timestamp(route.legs[-1].arrival_at);
        outside = instant > request_instant(request, zone);
    }
    if outside or instant.astimezone(ZoneInfo(zone)).date().isoformat() != request.local_date { reasons.append(ConstraintCode.OUTSIDE_WINDOW); }
    return reasons;
}

def risk_utility(level: RiskLevel) -> float {
    if level == RiskLevel.LOW { return 1.0; }
    if level == RiskLevel.MODERATE { return 0.5; }
    if level == RiskLevel.HIGH { return 0.0; }
    return 0.5;
}

def normalized_cost(value: float, values: list[float]) -> float {
    low = min(values); high = max(values);
    if high == low { return 1.0; }
    return (high - value) / (high - low);
}

def inferred_risk(request: TripRequest, route: RouteOption) -> RiskAssessment {
    delays = [leg.predicted_delay_minutes for leg in route.legs if leg.mode != TravelMode.WALK];
    known: list[int] = [];
    for delay in delays {
        if delay is not None { known.append(delay); }
    }
    level = RiskLevel.UNKNOWN;
    if known {
        worst = max(known);
        level = RiskLevel.LOW if worst < 15 else (RiskLevel.MODERATE if worst < 30 else RiskLevel.HIGH);
    }
    slack = transfer_slack(route);
    transfer = RiskLevel.MODERATE if slack and min(slack) < request.min_transfer_minutes + 15 else RiskLevel.LOW;
    return RiskAssessment(delay=level, transfer=transfer, weather=RiskLevel.UNKNOWN, uncertainty=0.25 if len(known) < len(delays) else 0.0);
}

"""Filter first, then normalize within feasible candidates; never mutates input."""
def rank_routes(request: TripRequest, candidates: list[RouteOption], as_of: str,
                risk_by_route: dict[str, RiskAssessment] | None = None) -> RankingResult {
    weights = preset_weights(PriorityPreset.BALANCED);
    rejected: list[RejectedRoute] = [];
    feasible: list[RouteOption] = [];
    try {
        _ = model_to_json(request);
        weights = preset_weights(request.priority);
        now = parse_timestamp(as_of);
        ids: set[str] = set();
        for route in candidates {
            _ = model_to_json(route);
            if risk_by_route is not None and route.id in risk_by_route { risk_by_route[route.id].validate(); }
            if route.id in ids { raise ValueError("duplicate route ID"); }
            ids.add(route.id);
            reasons = rejection_reasons(request, route);
            if reasons { rejected.append(RejectedRoute(route_id=route.id, reasons=reasons)); }
            else { feasible.append(route); }
        }
    } except (ValueError, TypeError, OverflowError) as error {
        return RankingResult([], [], weights, DomainError(ErrorCode.INVALID_REQUEST, str(error)));
    }
    if not feasible {
        return RankingResult([], rejected, weights, DomainError(ErrorCode.NO_ROUTES, "No routes satisfy all requested constraints."));
    }
    durations = [route.duration_minutes() for route in feasible];
    prices: list[float] = [];
    for route in feasible {
        if route.price_cents is not None { prices.append(float(route.price_cents)); }
    }
    scored: list[ScoredRoute] = [];
    for route in feasible {
        supplied = risk_by_route.get(route.id) if risk_by_route is not None else None;
        evidence = supplied if supplied is not None else inferred_risk(request, route);
        evidence.validate();
        stale = route.source.expires_at is not None and parse_timestamp(route.source.expires_at) <= now;
        unknown_price = route.price_cents is None;
        delay_level = RiskLevel.UNKNOWN if stale else evidence.delay;
        unknown_delay = delay_level == RiskLevel.UNKNOWN or `any([leg.predicted_delay_minutes is None for leg in route.legs if leg.mode != TravelMode.WALK]);
        unknown_weather = evidence.weather == RiskLevel.UNKNOWN;
        missing = float(int(unknown_price) + int(unknown_delay) + int(unknown_weather) + int(stale)) / 4.0;
        uncertainty = max(missing, evidence.uncertainty);
        price_feature = 0.5;
        if route.price_cents is not None { price_feature = normalized_cost(float(route.price_cents), prices); }
        features = ScoreDimensions(
            duration=normalized_cost(route.duration_minutes(), durations),
            reliability=risk_utility(delay_level), price=price_feature,
            transfers=risk_utility(evidence.transfer) / (1.0 + route.transfers()), weather=risk_utility(evidence.weather)
        );
        score = 100.0 * (weights.duration * features.duration + weights.reliability * features.reliability + weights.price * features.price + weights.transfers * features.transfers + weights.weather * features.weather) - 10.0 * uncertainty;
        codes = list(evidence.reason_codes);
        if route.duration_minutes() == min(durations) { codes.append(ReasonCode.FASTEST); }
        if route.price_cents is not None and float(route.price_cents) == min(prices) { codes.append(ReasonCode.LOWEST_COST); }
        if route.transfers() == min([item.transfers() for item in feasible]) { codes.append(ReasonCode.FEWEST_TRANSFERS); }
        if request.max_price_cents is not None and route.price_cents is not None { codes.append(ReasonCode.WITHIN_BUDGET); }
        if transfer_slack(route) and evidence.transfer in [RiskLevel.MODERATE, RiskLevel.HIGH] { codes.append(ReasonCode.TIGHT_TRANSFER); }
        if delay_level == RiskLevel.HIGH { codes.append(ReasonCode.DELAY_RISK_HIGH); }
        if evidence.weather == RiskLevel.HIGH { codes.append(ReasonCode.WEATHER_RISK_HIGH); }
        if missing > 0.0 { codes.append(ReasonCode.MISSING_DATA); }
        if stale { codes.append(ReasonCode.STALE_DATA); }
        codes = list(dict.fromkeys(codes));
        risk = RiskAssessment(delay=delay_level, transfer=evidence.transfer, weather=evidence.weather, uncertainty=uncertainty, reason_codes=codes);
        scored.append(ScoredRoute(option=route, risk=risk, features=features, score=round(score, 6), reason_codes=codes));
    }
    scored.sort(key=lambda (item: ScoredRoute) { (-item.score, item.option.transfers(), parse_timestamp(item.option.legs[-1].arrival_at).timestamp(), item.option.price_cents if item.option.price_cents is not None else float("inf"), item.option.id); });
    return RankingResult(scored, rejected, weights);
}
