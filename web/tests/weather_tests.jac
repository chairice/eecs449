import json;
import from pathlib { Path }
import from server.api { _plan_response, _trip_weather }
import from server.models {
    Place, ProviderMetadata, RiskLevel, RouteOption, SourceStatus, TimeKind, TripRequest,
    WeatherEvidence, model_to_json, model_to_object, parse_timestamp
}
import from server.planner { rank_routes }
import from server.providers.fixtures { FixtureRouteProvider }
import from server.providers.weather { NwsWeatherProvider, alert_level, route_samples }
import from server.weather_rules { by_significance, evidence_level, route_weather_level }

# Recorded api.weather.gov responses for Tuesday 2026-11-03, fetched on the 2nd.
glob RECORDED: Path = Path(__file__).resolve().parents[1] / "fixtures" / "weather";
glob AS_OF: str = "2026-11-02T02:40:00Z";

def recorded(name: str) -> object {
    return json.loads((RECORDED / name).read_text(encoding="utf-8"));
}

"""Stands in for api.weather.gov: answers from recorded responses and logs every URL."""
obj RecordedNws {
    has alerts: object, hourly: object, points: object;
    has fail: bool = False;
    has calls: list[str] postinit;
    def postinit { self.calls = []; }
    def get(url: str) -> object {
        self.calls.append(url);
        if self.fail { raise OSError("offline"); }
        if url.startswith("https://api.weather.gov/points/") { return self.points; }
        if url.startswith("https://api.weather.gov/alerts/active?point=") { return self.alerts; }
        if url.endswith("/forecast/hourly") { return self.hourly; }
        raise ValueError("unrecorded URL " + url);
    }
}

def nws(alerts: str = "alerts-none.json", fail: bool = False) -> RecordedNws {
    return RecordedNws(alerts=recorded(alerts), hourly=recorded("hourly-calm.json"), points=recorded("points-kalamazoo.json"), fail=fail);
}

def tuesday_request -> str {
    return model_to_json(TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-11-03", local_time="16:00", time_kind=TimeKind.DEPART_AFTER));
}

def tuesday_routes -> list[RouteOption] {
    result = FixtureRouteProvider().search(TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-11-03", local_time="16:00", time_kind=TimeKind.DEPART_AFTER));
    assert result.data is not None;
    return result.data;
}

def place -> Place { return Place(id="k", name="Kalamazoo", latitude=42.29, longitude=-85.58, timezone="America/Detroit"); }
def live -> ProviderMetadata { return ProviderMetadata(provider="nws", status=SourceStatus.LIVE, fetched_at=AS_OF); }
def reading(chance: float = 0.1, wind: float = 15.0, summary: str = "Mostly Cloudy", alert: RiskLevel = RiskLevel.LOW) -> WeatherEvidence {
    return WeatherEvidence(place=place(), valid_from="2026-11-03T17:00:00-05:00", valid_until="2026-11-03T18:00:00-05:00", source=live(), precipitation_probability=chance, wind_kph=wind, alert_severity=alert, summary=summary);
}
def unread -> WeatherEvidence {
    return WeatherEvidence(place=place(), valid_from="2026-11-03T17:00:00-05:00", valid_until="2026-11-03T18:00:00-05:00", source=ProviderMetadata(provider="nws", status=SourceStatus.UNAVAILABLE));
}

test "samples follow each vehicle from start to end with a point for every further hour" {
    for route in tuesday_routes() {
        samples = route_samples(route);
        assert samples[0].place.id == route.legs[0].origin.id and samples[-1].place.id == route.legs[-1].destination.id;
        assert all(samples[i].at <= samples[i + 1].at for i in range(len(samples) - 1));
        hours = route.duration_minutes() / 60.0;
        assert len(samples) >= hours + 1;
    }
}

test "forecast hazards alerts and calm hours set each point's level" {
    assert evidence_level(reading()) == RiskLevel.LOW;
    assert evidence_level(reading(chance=0.7, summary="Snow Likely")) == RiskLevel.MODERATE;
    assert evidence_level(reading(chance=0.7, summary="Rain Likely")) == RiskLevel.LOW;
    assert evidence_level(reading(chance=0.2, summary="Chance Snow Showers")) == RiskLevel.LOW;
    assert evidence_level(reading(wind=60.0)) == RiskLevel.MODERATE;
    assert evidence_level(reading(alert=RiskLevel.MODERATE)) == RiskLevel.MODERATE;
    assert evidence_level(reading(alert=RiskLevel.HIGH)) == RiskLevel.HIGH;
    assert evidence_level(reading(alert=RiskLevel.UNKNOWN)) == RiskLevel.UNKNOWN;
    assert evidence_level(reading(chance=0.8, summary="Freezing Rain", alert=RiskLevel.UNKNOWN)) == RiskLevel.MODERATE;
    assert evidence_level(unread()) == RiskLevel.UNKNOWN;
}

test "a route takes its worst point and unread points never read as safe" {
    assert route_weather_level([]) == RiskLevel.UNKNOWN;
    assert route_weather_level([reading(), reading()]) == RiskLevel.LOW;
    assert route_weather_level([reading(), unread()]) == RiskLevel.UNKNOWN;
    assert route_weather_level([unread(), reading(wind=70.0)]) == RiskLevel.MODERATE;
    assert route_weather_level([reading(wind=70.0), reading(alert=RiskLevel.HIGH)]) == RiskLevel.HIGH;
    ordered = by_significance([reading(), unread(), reading(alert=RiskLevel.HIGH)]);
    assert [evidence_level(item) for item in ordered] == [RiskLevel.HIGH, RiskLevel.LOW, RiskLevel.UNKNOWN];
}

test "warnings are high and watches advisories and moderate alerts are moderate" {
    assert alert_level({"event": "Winter Storm Warning", "severity": "Moderate"}) == RiskLevel.HIGH;
    assert alert_level({"event": "Blizzard Watch", "severity": "Severe"}) == RiskLevel.HIGH;
    assert alert_level({"event": "Winter Weather Advisory", "severity": "Minor"}) == RiskLevel.MODERATE;
    assert alert_level({"event": "Special Weather Statement", "severity": "Moderate"}) == RiskLevel.MODERATE;
    assert alert_level({"event": "Special Weather Statement", "severity": "Minor"}) == RiskLevel.LOW;
}

test "a calm recorded forecast with no alerts reads low along every route" {
    service = nws();
    result = NwsWeatherProvider(get_json=service.get).observe(tuesday_routes(), AS_OF);
    assert result.metadata.status == SourceStatus.LIVE and result.data is not None;
    for (_, evidence) in result.data.items() {
        assert evidence and route_weather_level(evidence) == RiskLevel.LOW;
        assert all(item.summary and item.alerts == [] for item in evidence);
        assert all(item.wind_kph is not None and 0.0 < item.wind_kph < 56.0 for item in evidence);
    }
}

test "a warning in force makes routes high risk and names the warning" {
    body = json.loads(_plan_response(tuesday_request(), FixtureRouteProvider(), AS_OF, NwsWeatherProvider(get_json=nws("alerts-winter-storm.json").get)));
    assert body["error"] is None and len(body["routes"]) == 3;
    assert [source["provider"] + ":" + source["status"] for source in body["sources"]] == ["detour-synthetic-corridor-v1:FIXTURE", "nws:LIVE"];
    for route in body["routes"] {
        assert route["risk"]["weather"] == "HIGH" and route["features"]["weather"] == 0.0;
        assert "WEATHER_RISK_HIGH" in route["reason_codes"];
        assert route["weather"][0]["alerts"] == ["Winter Storm Warning"];
    }
}

test "an advisory adds the weather advisory reason and halves weather utility" {
    advisory = {"features": [{"properties": {"event": "Winter Weather Advisory", "severity": "Minor", "onset": "2026-11-03T12:00:00-05:00", "ends": "2026-11-04T06:00:00-05:00"}}]};
    service = RecordedNws(alerts=advisory, hourly=recorded("hourly-calm.json"), points=recorded("points-kalamazoo.json"));
    body = json.loads(_plan_response(tuesday_request(), FixtureRouteProvider(), AS_OF, NwsWeatherProvider(get_json=service.get)));
    for route in body["routes"] {
        assert route["risk"]["weather"] == "MODERATE" and route["features"]["weather"] == 0.5;
        assert "WEATHER_ADVISORY" in route["reason_codes"] and "WEATHER_RISK_HIGH" not in route["reason_codes"];
    }
}

test "alerts that end before the trip are not in force" {
    over = {"features": [{"properties": {"event": "Winter Storm Warning", "severity": "Severe", "onset": "2026-11-02T00:00:00-05:00", "ends": "2026-11-03T06:00:00-05:00"}}]};
    service = RecordedNws(alerts=over, hourly=recorded("hourly-calm.json"), points=recorded("points-kalamazoo.json"));
    result = NwsWeatherProvider(get_json=service.get).observe(tuesday_routes(), AS_OF);
    assert result.data is not None;
    assert all(route_weather_level(evidence) == RiskLevel.LOW for evidence in result.data.values());
}

test "an unreachable weather service leaves weather unknown and keeps every route" {
    service = nws(fail=True);
    body = json.loads(_plan_response(tuesday_request(), FixtureRouteProvider(), AS_OF, NwsWeatherProvider(get_json=service.get)));
    assert body["error"] is None and len(body["routes"]) == 3;
    assert body["sources"][1]["status"] == "UNAVAILABLE";
    assert all(route["risk"]["weather"] == "UNKNOWN" and route["weather"] == [] for route in body["routes"]);
}

test "failed alert lookups keep calm forecasts unknown" {
    service = RecordedNws(alerts={"oops": True}, hourly=recorded("hourly-calm.json"), points=recorded("points-kalamazoo.json"));
    result = NwsWeatherProvider(get_json=service.get).observe(tuesday_routes(), AS_OF);
    assert result.data is not None;
    assert all(route_weather_level(evidence) == RiskLevel.UNKNOWN for evidence in result.data.values());
}

test "trips past the forecast horizon make no requests" {
    service = nws();
    result = NwsWeatherProvider(get_json=service.get).observe(tuesday_routes(), "2026-10-20T00:00:00Z");
    assert service.calls == [] and result.metadata.status == SourceStatus.UNAVAILABLE and result.data is None;
}

test "a forecast link off api.weather.gov is never followed" {
    points = {"properties": {"forecastHourly": "https://example.com/forecast/hourly"}};
    service = RecordedNws(alerts=recorded("alerts-none.json"), hourly=recorded("hourly-calm.json"), points=points);
    result = NwsWeatherProvider(get_json=service.get).observe(tuesday_routes(), AS_OF);
    assert not any("example.com" in url for url in service.calls);
    assert result.metadata.status == SourceStatus.UNAVAILABLE;
}

test "responses are cached across searches" {
    service = nws();
    provider = NwsWeatherProvider(get_json=service.get);
    _ = provider.observe(tuesday_routes(), AS_OF);
    first = len(service.calls);
    _ = provider.observe(tuesday_routes(), AS_OF);
    assert first > 0 and len(service.calls) == first;
}

test "unavailable weather evidence cannot carry a forecast summary or alerts" {
    with testraises(ValueError) {
        _ = WeatherEvidence(place=place(), valid_from="2026-11-03T17:00:00-05:00", valid_until="2026-11-03T18:00:00-05:00", source=ProviderMetadata(provider="nws", status=SourceStatus.UNAVAILABLE), summary="Snow");
    }
    with testraises(ValueError) {
        _ = WeatherEvidence(place=place(), valid_from="2026-11-03T17:00:00-05:00", valid_until="2026-11-03T18:00:00-05:00", source=live(), alerts=[""]);
    }
}

test "trips past the forecast keep weather unknown without counting it as missing" {
    early = "2026-10-20T00:00:00Z";
    service = nws();
    body = json.loads(_plan_response(tuesday_request(), FixtureRouteProvider(), early, NwsWeatherProvider(get_json=service.get)));
    assert service.calls == [] and body["error"] is None and len(body["routes"]) == 3;
    for route in body["routes"] {
        assert route["risk"]["weather"] == "UNKNOWN" and route["features"]["weather"] == 0.5;
        assert route["weather_from"] is not None and parse_timestamp(route["weather_from"]) > parse_timestamp(early);
        # Only the unknown delay counts as missing now: one quarter, not two.
        assert route["risk"]["uncertainty"] == 0.25;
    }
    near = json.loads(_plan_response(tuesday_request(), FixtureRouteProvider(), AS_OF, NwsWeatherProvider(get_json=nws().get)));
    assert all(route["weather_from"] is None for route in near["routes"]);
}

test "a hazard already forecast on a partly forecast trip still counts" {
    routes = tuesday_routes();
    request = TripRequest(origin_text="Ann Arbor", destination_text="Chicago", local_date="2026-11-03", local_time="16:00", time_kind=TimeKind.DEPART_AFTER);
    opens = {route.id: "2026-10-29T00:00:00-05:00" for route in routes};
    warned = rank_routes(request, routes, AS_OF, None, {route.id: [reading(alert=RiskLevel.HIGH)] for route in routes}, opens);
    assert all(item.risk.weather == RiskLevel.HIGH and item.weather_from is None for item in warned.routes);
    calm = rank_routes(request, routes, AS_OF, None, {route.id: [reading()] for route in routes}, opens);
    assert all(item.risk.weather == RiskLevel.UNKNOWN and item.weather_from is not None for item in calm.routes);
}

def saved_route_json(route: RouteOption) -> str {
    legs = [model_to_object(leg) for leg in route.legs];
    return json.dumps({"legs": [{key: leg[key] for key in ["id", "mode", "origin", "destination", "departure_at", "arrival_at", "path"]} for leg in legs]});
}

test "a saved route's weather is checked again with today's forecast" {
    payload = saved_route_json(tuesday_routes()[0]);
    calm = json.loads(_trip_weather(payload, AS_OF, NwsWeatherProvider(get_json=nws().get)));
    assert calm["error"] is None and calm["weather"] == "LOW" and calm["weather_from"] is None and calm["evidence"];
    stormy = json.loads(_trip_weather(payload, AS_OF, NwsWeatherProvider(get_json=nws("alerts-winter-storm.json").get)));
    assert stormy["weather"] == "HIGH" and stormy["evidence"][0]["alerts"] == ["Winter Storm Warning"];
    service = nws();
    early = json.loads(_trip_weather(payload, "2026-10-20T00:00:00Z", NwsWeatherProvider(get_json=service.get)));
    assert service.calls == [] and early["weather"] == "UNKNOWN" and early["weather_from"] is not None and early["error"] is None;
    off = json.loads(_trip_weather(payload, AS_OF, None));
    assert off["weather"] == "UNKNOWN" and off["error"]["code"] == "PROVIDER_UNAVAILABLE";
}

test "saved route checks refuse malformed, oversized and day-long legs" {
    route = json.loads(saved_route_json(tuesday_routes()[0]));
    long_leg = json.loads(json.dumps(route));
    long_leg["legs"][0]["arrival_at"] = "2026-11-05T21:40:00-06:00";
    many = {"legs": route["legs"] * 7};
    extra = json.loads(json.dumps(route));
    extra["legs"][0]["operator"] = "x";
    for payload in ["{", "[]", json.dumps({"legs": []}), json.dumps(long_leg), json.dumps(many), json.dumps(extra), " " * 300000] {
        result = json.loads(_trip_weather(payload, AS_OF, NwsWeatherProvider(get_json=nws().get)));
        assert result["error"]["code"] == "INVALID_REQUEST" and result["weather"] == "UNKNOWN";
    }
}
