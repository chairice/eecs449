"""Checked plain-JSON boundary and presentation formatting; never ranks routes."""

obj:pub ComparisonLeg {
    has id: str, mode: str, service: str, origin: str, destination: str, departure: str, arrival: str;
}
"""A stop the map can pin; only places that arrive with coordinates become one."""
obj:pub ComparisonStop {
    has name: str, latitude: float, longitude: float;
}
"""One leg as the map draws it: its mode and the points it runs through."""
obj:pub ComparisonSegment {
    has mode: str, points: list[list[float]];
}
obj:pub ComparisonRoute {
    has id: str, name: str, modes: str, departure: str, arrival: str, duration: str;
    has price: str, transfers: str, score: str, delay: str, weather: str, transfer_risk: str;
    has source: str, provider: str, freshness: str, source_time: str, source_warnings: list[str];
    has reasons: list[str], legs: list[ComparisonLeg];
    has stops: list[ComparisonStop] = [];
    # Fare in cents for totals; -1 when the fare is unknown.
    has price_cents: int = -1;
    has segments: list[ComparisonSegment] = [];
}
obj:pub ComparisonView {
    has valid: bool = False, error: str = "", error_code: str = "";
    has title: str = "", date: str = "", preference: str = "", routes: list[ComparisonRoute] = [];
}

def required_text(value: any) -> str {
    if not isinstance(value, str) { raise ValueError("Expected text in planning result"); }
    result = value as str;
    if not result.strip() { raise ValueError("Empty text in planning result"); }
    return result;
}
def required_number(value: any) -> float {
    if isinstance(value, bool) or not isinstance(value, (float, int)) { raise ValueError("Expected number in planning result"); }
    result = float(value);
    if not Number.isFinite(result) { raise ValueError("Nonfinite planning result"); }
    return result;
}
def required_list(value: any) -> list[any] {
    if not isinstance(value, list) { raise ValueError("Expected list in planning result"); }
    return value as list[any];
}

def instant_millis(timestamp: str) -> float {
    value: any = Date.parse(timestamp);
    if not Number.isFinite(value) { raise ValueError("Invalid route timestamp"); }
    return float(value);
}
def local_clock(timestamp: str, zone: str) -> str {
    _ = instant_millis(timestamp);
    clock: any = new(Date, timestamp);
    return str(clock.toLocaleTimeString("en-US", {"hour": "numeric", "minute": "2-digit", "timeZone": zone, "timeZoneName": "short"}));
}
def utc_label(timestamp: str) -> str {
    _ = instant_millis(timestamp);
    clock: any = new(Date, timestamp);
    return str(clock.toLocaleString("en-US", {"month": "short", "day": "numeric", "year": "numeric", "hour": "numeric", "minute": "2-digit", "timeZone": "UTC", "timeZoneName": "short"}));
}
def duration_label(departure: str, arrival: str) -> str {
    minutes = int((instant_millis(arrival) - instant_millis(departure)) / 60000.0);
    if minutes <= 0 { raise ValueError("Invalid route duration"); }
    return str(minutes // 60) + "h " + str(minutes % 60) + "m";
}
def price_label(value: any, currency: str) -> str {
    if value is None { return "Fare unavailable"; }
    cents = required_number(value);
    if cents < 0 or int(cents) != cents or currency != "USD" { raise ValueError("Invalid fare"); }
    # Fixed decimal formatting avoids browser locale ambiguity for this USD MVP.
    amount: any = cents / 100.0;
    return "$" + str(amount.toFixed(2)) + " USD";
}
def risk_label(value: any) -> str {
    level = required_text(value);
    if level == "LOW" { return "Low"; }
    if level == "MODERATE" { return "Moderate"; }
    if level == "HIGH" { return "High"; }
    if level == "UNKNOWN" { return "Unknown"; }
    raise ValueError("Invalid risk label");
}
def mode_label(value: any) -> str {
    mode = required_text(value);
    if mode == "TRAIN" { return "Train"; }
    if mode == "BUS" { return "Bus"; }
    if mode == "WALK" { return "Walk"; }
    raise ValueError("Invalid route mode");
}
def reason_label(code: str) -> str {
    if code == "FASTEST" { return "Shortest journey among these options"; }
    if code == "LOWEST_COST" { return "Lowest known fare among these options"; }
    if code == "FEWEST_TRANSFERS" { return "Fewest vehicle changes among these options"; }
    if code == "WITHIN_BUDGET" { return "Within your maximum price"; }
    if code == "TIGHT_TRANSFER" { return "A connection has limited extra buffer"; }
    if code == "DELAY_RISK_HIGH" { return "Higher delay risk in the available evidence"; }
    if code == "WEATHER_RISK_HIGH" { return "Higher weather risk in the available evidence"; }
    if code == "WEATHER_ADVISORY" { return "Weather may affect this journey"; }
    if code == "MISSING_DATA" { return "Some fare, delay, or weather information is unknown"; }
    if code == "STALE_DATA" { return "Some source information is out of date"; }
    return "Additional provider advisory: " + code;
}
def preference_label(value: str) -> str {
    if value == "FASTEST" { return "Fastest journey"; }
    if value == "LOWEST_COST" { return "Lowest cost"; }
    if value == "MOST_RELIABLE" { return "Most reliable"; }
    if value == "FEWEST_TRANSFERS" { return "Fewest transfers"; }
    return "Balanced priorities";
}

def map_stop(place: any) -> ComparisonStop | None {
    latitude = place["latitude"]; longitude = place["longitude"];
    for value in [latitude, longitude] {
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not Number.isFinite(value) { return None; }
    }
    return ComparisonStop(name=required_text(place["name"]), latitude=float(latitude), longitude=float(longitude));
}

"""Origin, every change point, and destination; empty unless all are mappable."""
def route_stops(raw_legs: list[any]) -> list[ComparisonStop] {
    stops: list[ComparisonStop] = [];
    for place in [raw_legs[0]["origin"]] + [leg["destination"] for leg in raw_legs] {
        stop = map_stop(place);
        if stop is None { return []; }
        stops.append(stop);
    }
    return stops;
}

def map_point(value: any) -> list[float] | None {
    if not isinstance(value, list) or len(value) != 2 { return None; }
    for number in value {
        if isinstance(number, bool) or not isinstance(number, (float, int)) or not Number.isFinite(number) { return None; }
    }
    return [float(value[0]), float(value[1])];
}

"""Each leg's drawn path; a leg without one is a straight line between its stops,
and a route with any unmappable leg draws nothing rather than guess."""
def route_segments(raw_legs: list[any]) -> list[ComparisonSegment] {
    segments: list[ComparisonSegment] = [];
    for leg in raw_legs {
        points: list[list[float]] = [];
        drawn: any = leg["path"];
        if isinstance(drawn, list) and len(drawn) >= 2 {
            for value in drawn {
                point = map_point(value);
                if point is None { return []; }
                points.append(point);
            }
        } else {
            start = map_stop(leg["origin"]);
            end = map_stop(leg["destination"]);
            if start is None or end is None { return []; }
            points = [[start.latitude, start.longitude], [end.latitude, end.longitude]];
        }
        segments.append(ComparisonSegment(mode=mode_label(leg["mode"]), points=points));
    }
    return segments;
}

def route_view(raw: any, as_of: str) -> ComparisonRoute {
    option = raw["option"];
    legs: list[ComparisonLeg] = [];
    modes: list[str] = [];
    services: list[str] = [];
    transit_count = 0;
    for leg in required_list(option["legs"]) {
        mode = mode_label(leg["mode"]);
        service = required_text(leg["service"]) if leg["service"] else mode;
        if mode != "Walk" { transit_count += 1; }
        if mode not in modes { modes.append(mode); }
        services.append(service);
        legs.append(ComparisonLeg(id=required_text(leg["id"]), mode=mode, service=service,
            origin=required_text(leg["origin"]["name"]), destination=required_text(leg["destination"]["name"]),
            departure=local_clock(required_text(leg["departure_at"]), required_text(leg["origin"]["timezone"])),
            arrival=local_clock(required_text(leg["arrival_at"]), required_text(leg["destination"]["timezone"]))));
    }
    if len(legs) == 0 { raise ValueError("Route has no legs"); }
    raw_legs = required_list(option["legs"]);
    first = raw_legs[0]; last = raw_legs[len(raw_legs) - 1];
    source = option["source"];
    source_mode = required_text(source["status"]);
    if source_mode not in ["FIXTURE", "LIVE", "CACHED"] { raise ValueError("Invalid route provenance"); }
    stale = bool(source["expires_at"]) and instant_millis(required_text(source["expires_at"])) <= instant_millis(as_of);
    has_freshness = bool(source["expires_at"]) and bool(source["fetched_at"]);
    freshness = "Synthetic example" if source_mode == "FIXTURE" else "Out of date" if stale else "Current at search" if has_freshness else "Freshness unknown";
    if stale { freshness += " · stale"; }
    warnings = [required_text(warning["message"]) for warning in required_list(source["warnings"])];
    reasons = [reason_label(required_text(code)) for code in required_list(raw["reason_codes"])];
    transfers = max(0, transit_count - 1);
    score_value: any = required_number(raw["score"]);
    return ComparisonRoute(id=required_text(option["id"]), name=" + ".join(services), modes=" + ".join(modes),
        departure=legs[0].departure, arrival=legs[len(legs) - 1].arrival,
        duration=duration_label(required_text(first["departure_at"]), required_text(last["arrival_at"])),
        price=price_label(option["price_cents"], required_text(option["currency"])),
        transfers="Direct" if transfers == 0 else str(transfers) + (" transfer" if transfers == 1 else " transfers"),
        score=str(score_value.toFixed(1)), delay=risk_label(raw["risk"]["delay"]), weather=risk_label(raw["risk"]["weather"]),
        transfer_risk=risk_label(raw["risk"]["transfer"]), source=source_mode, provider=required_text(source["provider"]),
        freshness=freshness, source_time=utc_label(required_text(source["fetched_at"])) if source["fetched_at"] else "Timestamp unavailable", source_warnings=warnings,
        reasons=reasons, legs=legs, stops=route_stops(raw_legs), segments=route_segments(raw_legs),
        price_cents=-1 if option["price_cents"] is None else int(required_number(option["price_cents"])));
}

def:pub comparison_view(preview: any) -> ComparisonView {
    if not preview { return ComparisonView(); }
    try {
        if preview["schema_version"] != 1 or preview["mode"] != "FIXTURE" { raise ValueError("Unsupported planning result"); }
        if preview["error"] {
            return ComparisonView(valid=True, error=required_text(preview["error"]["message"]), error_code=required_text(preview["error"]["code"]));
        }
        request = preview["request"];
        routes = [route_view(raw, required_text(preview["as_of"])) for raw in required_list(preview["routes"])];
        ids: list[str] = [];
        for route in routes {
            if route.id in ids { raise ValueError("Duplicate route option"); }
            ids.append(route.id);
        }
        if not routes { return ComparisonView(valid=True, error="No routes match your trip details. Try another time, budget, or transfer buffer.", error_code="NO_ROUTES"); }
        return ComparisonView(valid=True, title=required_text(request["origin_text"]) + " → " + required_text(request["destination_text"]),
            date=required_text(request["local_date"]), preference=preference_label(required_text(request["priority"])), routes=routes);
    } except Exception {
        return ComparisonView(error="This comparison could not be read. Return to planning and search again.", error_code="INVALID_PREVIEW");
    }
}
