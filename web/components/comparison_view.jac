"""Checked plain-JSON boundary and presentation formatting; never ranks routes."""

obj:pub ComparisonLeg {
    has id: str, mode: str, service: str, origin: str, destination: str, departure: str, arrival: str;
    # Whole minutes between the previous leg's arrival and this leg's departure; 0 for the first leg.
    has layover_minutes: int = 0;
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
    # What set the weather level, in a few words for a card and a sentence for the booking panel.
    has weather_brief: str = "", weather_note: str = "";
    # "Thu, Nov 12" while forecasts don't yet reach the trip, else "".
    has weather_from: str = "";
    # The departure's local day: "Thu, Nov 5", its ISO date, and its instant for ordering.
    has day: str = "", date_iso: str = "", departure_ms: float = 0.0;
    # When the last leg arrives, so a return can be matched to an outbound.
    has arrival_ms: float = 0.0;
    # "Wed, Nov 4, 10:30 PM CST": the arrival with its day, in the destination's zone.
    has arrives: str = "";
    # Time spent between vehicles, already inside `duration`: "50 min connection at Kalamazoo".
    has connections: str = "";
    # The legs as the planner sent them, minus status fields, so a saved trip can re-check its weather.
    has weather_legs: list[any] = [];
}
obj:pub ComparisonView {
    has valid: bool = False, error: str = "", error_code: str = "";
    has title: str = "", date: str = "", preference: str = "", routes: list[ComparisonRoute] = [];
    has time_kind: str = "", local_time: str = "";
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
"""Elapsed minutes as people say them: 50 as "50 min", 65 as "1 hr 5 min", 120 as "2 hr"."""
def minutes_words(minutes: int) -> str {
    if minutes < 60 { return str(minutes) + " min"; }
    rest = minutes % 60;
    return str(minutes // 60) + " hr" + ("" if rest == 0 else " " + str(rest) + " min");
}

"""Each change between vehicles and how long it takes, from the previous vehicle's
arrival to the next one's departure (any walk between them included). Total travel
time already spans these, since it runs from first departure to final arrival."""
def connection_label(raw_legs: list[any]) -> str {
    parts: list[str] = [];
    previous: any = None;
    for leg in raw_legs {
        if mode_label(leg["mode"]) == "Walk" { continue; }
        if previous is not None {
            minutes = int((instant_millis(required_text(leg["departure_at"])) - instant_millis(required_text(previous["arrival_at"]))) / 60000.0);
            parts.append(minutes_words(minutes) + " connection at " + required_text(previous["destination"]["name"]));
        }
        previous = leg;
    }
    return ", ".join(parts);
}

def price_label(value: any, currency: str) -> str {
    if value is None { return "Fare unavailable"; }
    cents = required_number(value);
    if cents < 0 or int(cents) != cents or currency != "USD" { raise ValueError("Invalid fare"); }
    # Fixed decimal formatting avoids browser locale ambiguity for this USD MVP.
    amount: any = cents / 100.0;
    return "$" + str(amount.toFixed(2)) + " USD";
}
def:pub risk_label(value: any) -> str {
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

"""The forecast point that set the route's weather level, as (brief, sentence).
The server lists the most significant point first; unknown weather says so."""
def:pub weather_words(raw: list[any], level: str, opens: str) -> tuple[str, str] {
    if opens {
        return ("Forecast from " + opens, "Weather isn't forecast this far ahead. Detour will rate it from " + opens + ".");
    }
    if level == "Unknown" {
        return ("No forecast yet", "Detour couldn't get a forecast for all of this trip, so weather is unknown, not clear.");
    }
    if len(raw) == 0 { return ("", ""); }
    first = raw[0];
    place = required_text(first["place"]["name"]);
    where = "e" + place[1:] if place.startswith("En route") else "near " + place;
    when = local_clock(required_text(first["valid_from"]), required_text(first["place"]["timezone"]));
    alerts = required_list(first["alerts"]);
    summary = str(first["summary"]) if first["summary"] else "Forecast";
    if len(alerts) > 0 {
        alert = required_text(alerts[0]);
        return (alert, alert + " in force " + where + " around " + when + ".");
    }
    if level == "Low" { return (summary, summary + " along the way, with no weather alerts in force."); }
    mph: any = 0.0 if first["wind_kph"] is None else required_number(first["wind_kph"]) / 1.609344;
    gusty = ", winds near " + str(mph.toFixed(0)) + " mph" if mph >= 25.0 else "";
    return (summary, summary + gusty + " " + where + " around " + when + ".");
}

def:pub day_label(timestamp: str, zone: str) -> str {
    _ = instant_millis(timestamp);
    day: any = new(Date, timestamp);
    return str(day.toLocaleDateString("en-US", {"weekday": "short", "month": "short", "day": "numeric", "timeZone": zone}));
}

def iso_day(timestamp: str, zone: str) -> str {
    _ = instant_millis(timestamp);
    day: any = new(Date, timestamp);
    return str(day.toLocaleDateString("en-CA", {"year": "numeric", "month": "2-digit", "day": "2-digit", "timeZone": zone}));
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
    previous_arrival = "";
    for leg in required_list(option["legs"]) {
        mode = mode_label(leg["mode"]);
        layover = 0;
        if previous_arrival {
            layover = int((instant_millis(required_text(leg["departure_at"])) - instant_millis(previous_arrival)) / 60000.0);
        }
        previous_arrival = required_text(leg["arrival_at"]);
        service = required_text(leg["service"]) if leg["service"] else mode;
        if mode != "Walk" { transit_count += 1; }
        if mode not in modes { modes.append(mode); }
        services.append(service);
        legs.append(ComparisonLeg(id=required_text(leg["id"]), mode=mode, service=service,
            origin=required_text(leg["origin"]["name"]), destination=required_text(leg["destination"]["name"]),
            departure=local_clock(required_text(leg["departure_at"]), required_text(leg["origin"]["timezone"])),
            arrival=local_clock(required_text(leg["arrival_at"]), required_text(leg["destination"]["timezone"])),
            layover_minutes=layover));
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
    weather = risk_label(raw["risk"]["weather"]);
    opens = day_label(required_text(raw["weather_from"]), required_text(last["destination"]["timezone"])) if raw["weather_from"] else "";
    if opens { weather = "Not yet forecast"; }
    words = weather_words(required_list(raw["weather"]) if raw["weather"] else [], weather, opens);
    return ComparisonRoute(id=required_text(option["id"]), name=" + ".join(services), modes=" + ".join(modes),
        departure=legs[0].departure, arrival=legs[len(legs) - 1].arrival,
        duration=duration_label(required_text(first["departure_at"]), required_text(last["arrival_at"])),
        price=price_label(option["price_cents"], required_text(option["currency"])),
        transfers="Direct" if transfers == 0 else str(transfers) + (" transfer" if transfers == 1 else " transfers"),
        score=str(score_value.toFixed(1)), delay=risk_label(raw["risk"]["delay"]), weather=weather, weather_brief=words[0], weather_note=words[1], weather_from=opens,
        day=day_label(required_text(first["departure_at"]), required_text(first["origin"]["timezone"])),
        date_iso=iso_day(required_text(first["departure_at"]), required_text(first["origin"]["timezone"])),
        departure_ms=instant_millis(required_text(first["departure_at"])),
        arrival_ms=instant_millis(required_text(last["arrival_at"])),
        weather_legs=[{"id": leg["id"], "mode": leg["mode"], "origin": leg["origin"], "destination": leg["destination"],
            "departure_at": leg["departure_at"], "arrival_at": leg["arrival_at"], "path": leg["path"] if leg["path"] else []} for leg in raw_legs],
        connections=connection_label(raw_legs),
        arrives=day_label(required_text(last["arrival_at"]), required_text(last["destination"]["timezone"])) + ", " + legs[len(legs) - 1].arrival,
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
            date=required_text(request["local_date"]), preference=preference_label(required_text(request["priority"])), routes=routes,
            time_kind=required_text(request["time_kind"]), local_time=required_text(request["local_time"]));
    } except Exception {
        return ComparisonView(error="This comparison could not be read. Return to planning and search again.", error_code="INVALID_PREVIEW");
    }
}
