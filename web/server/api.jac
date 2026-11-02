"""
Stateless fixture planning RPC. This endpoint never creates or saves a draft.

Input is the explicit TripRequest JSON contract, limited to 16 KiB UTF-8.
Output is JSON with schema_version, mode, request, as_of, routes, rejected,
weights, sources, and error. Routes carry live National Weather Service evidence
when it can be read (set DETOUR_WEATHER=off to skip it); otherwise their weather
stays unknown. All provider candidates survive until ranking;
the response returns every feasible ranked option. Fixture dates may be past
or future because these are synthetic examples, never bookable schedules.
"""

import json;
import from datetime { datetime, timezone }
import from os { environ }
import from server.models {
    DomainError, ErrorCode, ProviderMetadata, RiskLevel, RouteLeg, RouteOption, SourceStatus, TravelMode, WeatherEvidence,
    check_keys, json_array, json_object, json_text, parse_timestamp, path_from_array, place_from_object,
    model_to_object as _model_to_object,
    trip_request_from_json as _trip_request_from_json
}
import from server.planner { rank_routes as _rank_routes }
import from server.providers.fixtures { FixtureRouteProvider }
import from server.providers.route_provider { RouteProvider }
import from server.providers.weather { NwsWeatherProvider, WeatherProvider }
import from server.weather_rules { by_significance, pending_weather, route_weather_level }

glob MAX_REQUEST_BYTES: int = 16384;
# A saved route carries its drawn path, so it may be larger than a search.
glob MAX_ROUTE_BYTES: int = 262144;
glob MAX_SAVED_LEGS: int = 6;
glob MAX_LEG_HOURS: float = 24.0;
# One provider for the server's life, so its forecast cache is shared across searches.
glob LIVE_WEATHER: NwsWeatherProvider = NwsWeatherProvider();

"""The single anonymous endpoint reads committed synthetic routes and live weather."""
def:pub plan_trip(request_json: str) -> str {
    weather = None if environ.get("DETOUR_WEATHER", "").casefold() == "off" else LIVE_WEATHER;
    return _plan_response(request_json, FixtureRouteProvider(), datetime.now(timezone.utc).isoformat(), weather);
}

"""Injected dependencies keep boundary tests deterministic without exposing knobs over RPC.
Without a weather provider every route's weather is unknown."""
def _plan_response(request_json: str, provider: RouteProvider, as_of: str, weather: WeatherProvider | None = None) -> str {
    body: dict[str, object] = {
        "schema_version": 1, "mode": "FIXTURE", "request": None,
        "as_of": as_of, "routes": [], "rejected": [], "weights": None,
        "sources": [], "error": None
    };
    try {
        if not isinstance(request_json, str) or len(request_json.encode("utf-8")) > MAX_REQUEST_BYTES {
            raise ValueError("invalid request payload");
        }
        request = _trip_request_from_json(request_json);
    } except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError) {
        return _failed_response(body, DomainError(ErrorCode.INVALID_REQUEST, "Provide a valid structured trip request of at most 16 KiB."));
    }
    body["request"] = _model_to_object(request);
    provided = provider.search(request, as_of);
    body["sources"] = [_model_to_object(provided.metadata)];
    if provided.error is not None {
        return _failed_response(body, provided.error);
    }
    if provided.data is None {
        return _failed_response(body, DomainError(ErrorCode.PROVIDER_UNAVAILABLE, "The synthetic route provider did not return candidates."));
    }
    candidates: list[RouteOption] = provided.data;
    weather_by_route: dict[str, list[WeatherEvidence]] | None = None;
    weather_from: dict[str, str] = {};
    if weather is not None and candidates {
        observed = weather.observe(candidates, as_of);
        body["sources"] = [_model_to_object(provided.metadata), _model_to_object(observed.metadata)];
        weather_by_route = observed.data;
        for route in candidates {
            opens = weather.forecast_from(route, as_of);
            if opens is not None { weather_from[route.id] = opens; }
        }
    }
    ranked = _rank_routes(request, candidates, as_of, None, weather_by_route, weather_from);
    body["weights"] = _model_to_object(ranked.weights);
    body["rejected"] = [{"route_id": item.route_id, "reasons": list(item.reasons)} for item in ranked.rejected];
    if ranked.error is not None {
        error = ranked.error;
        if error.code == ErrorCode.INVALID_REQUEST {
            error = DomainError(ErrorCode.INVALID_REQUEST, "Choose valid trip fields and an unambiguous local departure or arrival time.");
        }
        return _failed_response(body, error);
    }
    body["routes"] = _model_to_object(ranked.routes);
    return json.dumps(body, allow_nan=False, sort_keys=True);
}

def _failed_response(body: dict[str, object], error: DomainError) -> str {
    body["error"] = _model_to_object(error);
    return json.dumps(body, allow_nan=False, sort_keys=True);
}

"""Today's weather for one saved route, so a saved trip can show what the
forecast says now rather than when it was saved. Input is {"legs": [...]} with
each leg's id, mode, origin, destination, departure_at, arrival_at and path, as
the planner returned them. Output is JSON with weather, weather_from, evidence
and error; nothing is stored."""
def:pub trip_weather(route_json: str) -> str {
    weather = None if environ.get("DETOUR_WEATHER", "").casefold() == "off" else LIVE_WEATHER;
    return _trip_weather(route_json, datetime.now(timezone.utc).isoformat(), weather);
}

def _trip_weather(route_json: str, as_of: str, weather: WeatherProvider | None) -> str {
    body: dict[str, object] = {"as_of": as_of, "weather": RiskLevel.UNKNOWN, "weather_from": None, "evidence": [], "error": None};
    try {
        if not isinstance(route_json, str) or len(route_json.encode("utf-8")) > MAX_ROUTE_BYTES { raise ValueError("invalid route payload"); }
        route = _saved_route(route_json, as_of);
    } except (ValueError, TypeError, KeyError, OverflowError, RecursionError, UnicodeError) {
        body["error"] = _model_to_object(DomainError(ErrorCode.INVALID_REQUEST, "Provide a saved route of at most six legs, each under a day long."));
        return json.dumps(body, allow_nan=False, sort_keys=True);
    }
    if weather is None {
        body["error"] = _model_to_object(DomainError(ErrorCode.PROVIDER_UNAVAILABLE, "Live weather is turned off on this server."));
        return json.dumps(body, allow_nan=False, sort_keys=True);
    }
    observed = weather.observe([route], as_of);
    evidence = observed.data.get(route.id, []) if observed.data is not None else [];
    settled = pending_weather(route_weather_level(evidence) if evidence else RiskLevel.UNKNOWN, weather.forecast_from(route, as_of));
    body["weather"] = settled[0];
    body["weather_from"] = settled[1];
    body["evidence"] = _model_to_object(by_significance(evidence));
    if observed.error is not None and settled[1] is None { body["error"] = _model_to_object(observed.error); }
    return json.dumps(body, allow_nan=False, sort_keys=True);
}

def _saved_route(route_json: str, as_of: str) -> RouteOption {
    raw = json_object(json.loads(route_json));
    check_keys(raw, ["legs"]);
    items = json_array(raw.get("legs"));
    if not items or len(items) > MAX_SAVED_LEGS { raise ValueError("a saved route has one to six legs"); }
    legs: list[RouteLeg] = [];
    for item in items {
        leg = json_object(item);
        check_keys(leg, ["id", "mode", "origin", "destination", "departure_at", "arrival_at", "path"]);
        built = RouteLeg(id=json_text(leg.get("id")), mode=TravelMode(json_text(leg.get("mode"))),
            origin=place_from_object(leg.get("origin")), destination=place_from_object(leg.get("destination")),
            departure_at=json_text(leg.get("departure_at")), arrival_at=json_text(leg.get("arrival_at")),
            path=path_from_array(leg.get("path", [])));
        # Long legs would mean many forecast points; real legs on this corridor take hours.
        if (parse_timestamp(built.arrival_at) - parse_timestamp(built.departure_at)).total_seconds() > MAX_LEG_HOURS * 3600.0 { raise ValueError("leg too long"); }
        legs.append(built);
    }
    return RouteOption(id="saved-route", legs=legs, source=ProviderMetadata(provider="saved-trip", status=SourceStatus.CACHED, fetched_at=as_of));
}
