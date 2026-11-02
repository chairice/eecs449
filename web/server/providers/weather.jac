"""
National Weather Service evidence along a route: the hourly forecast and the
alerts in force where a traveler will be, at the hour they will be there.

api.weather.gov needs no key but asks for an identifying User-Agent; set
DETOUR_NWS_CONTACT to a contact address or URL for deployed servers. Grid
lookups, forecasts and alerts are cached briefly and fetched in parallel within
a fixed time budget. Nothing here raises into planning: a point that cannot be
read comes back UNAVAILABLE, which ranks as unknown weather."""

import json;
import threading;
import time;
import from concurrent.futures { ThreadPoolExecutor }
import from datetime { datetime, timedelta }
import from math { ceil }
import from os { environ }
import from urllib.request { Request, urlopen }
import from server.models {
    DomainError, ErrorCode, Place, ProviderMetadata, ProviderResult, ProviderWarning, RiskLevel,
    RouteOption, SourceStatus, TravelMode, WeatherEvidence,
    json_array, json_number, json_object, json_text, parse_timestamp
}

glob NWS_BASE: str = "https://api.weather.gov";
glob PROVIDER: str = "nws";
# forecastHourly runs about 156 hours ahead; later hours have no forecast yet.
glob HORIZON_HOURS: float = 150.0;
glob SAMPLE_MINUTES: float = 60.0;
glob FETCH_TIMEOUT_SECONDS: float = 4.0;
glob BUDGET_SECONDS: float = 8.0;
glob POINT_TTL_SECONDS: float = 86400.0;
glob FORECAST_TTL_SECONDS: float = 900.0;
glob ALERT_TTL_SECONDS: float = 300.0;
glob KPH_PER_MPH: float = 1.609344;

def user_agent -> str {
    return "Detour/0.1 (EECS 449 trip planner; " + environ.get("DETOUR_NWS_CONTACT", "student project") + ")";
}

def nws_get(url: str) -> object {
    request = Request(url, headers={"User-Agent": user_agent(), "Accept": "application/geo+json"});
    with urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as response {
        return json.loads(response.read().decode("utf-8"));
    }
}

"""Where a traveler is and when."""
obj RouteSample {
    has place: Place, at: datetime;
}

"""Each vehicle's start and end, and a point on its path for every further
hour aboard. Walking legs are skipped; a leg without a path is a straight line."""
def:pub route_samples(route: RouteOption) -> list[RouteSample] {
    samples: list[RouteSample] = [];
    for leg in route.legs {
        if leg.mode == TravelMode.WALK { continue; }
        start = parse_timestamp(leg.departure_at);
        end = parse_timestamp(leg.arrival_at);
        samples.append(RouteSample(place=leg.origin, at=start));
        steps = int(ceil((end - start).total_seconds() / 60.0 / SAMPLE_MINUTES));
        for step in range(1, steps) {
            share = step / steps;
            latitude = leg.origin.latitude + share * (leg.destination.latitude - leg.origin.latitude);
            longitude = leg.origin.longitude + share * (leg.destination.longitude - leg.origin.longitude);
            if leg.path {
                point = leg.path[round(share * (len(leg.path) - 1))];
                latitude = point[0];
                longitude = point[1];
            }
            place = Place(id=leg.id + "-" + str(step), name="En route to " + leg.destination.name,
                latitude=latitude, longitude=longitude, timezone=leg.origin.timezone);
            samples.append(RouteSample(place=place, at=start + (end - start) * share));
        }
        samples.append(RouteSample(place=leg.destination, at=end));
    }
    return samples;
}

"""NWS reads at most four decimals of a coordinate."""
def point_key(place: Place) -> str {
    return str(round(place.latitude, 4)) + "," + str(round(place.longitude, 4));
}

"""Warnings and severe alerts are HIGH; watches, advisories and moderate ones
MODERATE; anything else in force is LOW."""
def:pub alert_level(alert: dict[str, object]) -> RiskLevel {
    event = str(alert.get("event") or "");
    severity = str(alert.get("severity") or "");
    if severity in ["Extreme", "Severe"] or event.endswith("Warning") { return RiskLevel.HIGH; }
    if severity == "Moderate" or event.endswith("Advisory") or event.endswith("Watch") { return RiskLevel.MODERATE; }
    return RiskLevel.LOW;
}

def alert_in_force(alert: dict[str, object], at: datetime) -> bool {
    start = alert.get("onset") or alert.get("effective");
    end = alert.get("ends") or alert.get("expires");
    if start is not None and parse_timestamp(json_text(start)) > at { return False; }
    return end is None or parse_timestamp(json_text(end)) > at;
}

"""The fastest speed in "10 mph" or "10 to 15 mph", in km/h."""
def wind_kph(text: object) -> float | None {
    speeds = [float(word) for word in str(text or "").split() if word.isdigit()];
    return max(speeds) * KPH_PER_MPH if speeds else None;
}

def chance(value: object) -> float | None {
    if value is None { return None; }
    raw = json_object(value).get("value");
    return None if raw is None else min(1.0, max(0.0, json_number(raw) / 100.0));
}

"""What one point returned; None where that request failed."""
obj PointWeather {
    has periods: list[object] | None = None, alerts: list[dict[str, object]] | None = None;
}

obj WeatherProvider {
    def observe(routes: list[RouteOption], as_of: str) -> ProviderResult[dict[str, list[WeatherEvidence]]] {
        _ = (routes, as_of);
        raise NotImplementedError("WeatherProvider.observe requires an adapter");
    }
    """When forecasts will first reach the trip's arrival, or None once they do."""
    def forecast_from(route: RouteOption, as_of: str) -> str | None {
        _ = (route, as_of);
        raise NotImplementedError("WeatherProvider.forecast_from requires an adapter");
    }
}

obj NwsWeatherProvider(WeatherProvider) {
    # Tests pass recorded responses here; None calls api.weather.gov.
    has get_json: Callable[[str], object] | None = None;
    has cache: dict[str, tuple[float, object]] postinit, lock: threading.Lock postinit;

    def postinit {
        self.cache = {};
        self.lock = threading.Lock();
    }

    def cached(url: str, ttl: float) -> object {
        now = time.monotonic();
        with self.lock {
            hit = self.cache.get(url);
        }
        if hit is not None and hit[0] > now { return hit[1]; }
        body = self.get_json(url) if self.get_json is not None else nws_get(url);
        with self.lock {
            self.cache[url] = (now + ttl, body);
        }
        return body;
    }

    def read_point(key: str) -> PointWeather {
        result = PointWeather();
        try {
            grid = json_object(json_object(self.cached(NWS_BASE + "/points/" + key, POINT_TTL_SECONDS)).get("properties"));
            hourly_url = json_text(grid.get("forecastHourly"));
            if not hourly_url.startswith(NWS_BASE + "/") { raise ValueError("forecast is not on api.weather.gov"); }
            hourly = json_object(json_object(self.cached(hourly_url, FORECAST_TTL_SECONDS)).get("properties"));
            result.periods = json_array(hourly.get("periods"));
        } except Exception {
            result.periods = None;
        }
        try {
            alerts = json_object(self.cached(NWS_BASE + "/alerts/active?point=" + key, ALERT_TTL_SECONDS));
            result.alerts = [json_object(json_object(feature).get("properties")) for feature in json_array(alerts.get("features"))];
        } except Exception {
            result.alerts = None;
        }
        return result;
    }

    """Each point once, all at the same time; whatever misses the budget is unread."""
    def read_points(keys: list[str]) -> dict[str, PointWeather] {
        readings: dict[str, PointWeather] = {};
        if not keys { return readings; }
        pool = ThreadPoolExecutor(max_workers=min(8, len(keys)));
        futures = {key: pool.submit(self.read_point, key) for key in keys};
        deadline = time.monotonic() + BUDGET_SECONDS;
        for (key, future) in futures.items() {
            try {
                readings[key] = future.result(timeout=max(0.0, deadline - time.monotonic()));
            } except Exception {
                continue;
            }
        }
        # Don't hold the request for stragglers; their threads end on their own timeouts.
        pool.shutdown(False, cancel_futures=True);
        return readings;
    }

    def forecast_from(route: RouteOption, as_of: str) -> str | None {
        reach = timedelta(hours=HORIZON_HOURS);
        arrival = parse_timestamp(route.legs[-1].arrival_at);
        if arrival <= parse_timestamp(as_of) + reach { return None; }
        return (arrival - reach).isoformat();
    }

    def observe(routes: list[RouteOption], as_of: str) -> ProviderResult[dict[str, list[WeatherEvidence]]] {
        now = parse_timestamp(as_of);
        horizon = now + timedelta(hours=HORIZON_HOURS);
        plans = {route.id: route_samples(route) for route in routes};
        keys: list[str] = [];
        for samples in plans.values() {
            for sample in samples {
                key = point_key(sample.place);
                if now - timedelta(hours=1) <= sample.at <= horizon and key not in keys { keys.append(key); }
            }
        }
        readings = self.read_points(keys);
        read_any = `any([reading.periods is not None for reading in readings.values()]);
        if not read_any {
            message = "The National Weather Service couldn't be reached." if keys else "Forecasts don't reach this trip's dates yet.";
            return ProviderResult(metadata=ProviderMetadata(provider=PROVIDER, status=SourceStatus.UNAVAILABLE),
                error=DomainError(code=ErrorCode.PROVIDER_UNAVAILABLE, message=message, retryable=bool(keys)));
        }
        live = ProviderMetadata(provider=PROVIDER, status=SourceStatus.LIVE, fetched_at=as_of, expires_at=(now + timedelta(hours=1)).isoformat());
        by_route: dict[str, list[WeatherEvidence]] = {};
        missing = 0;
        for (route_id, samples) in plans.items() {
            evidence: list[WeatherEvidence] = [];
            for sample in samples {
                item = sample_evidence(sample, readings.get(point_key(sample.place)), live, horizon);
                if item.source.status == SourceStatus.UNAVAILABLE { missing += 1; }
                evidence.append(item);
            }
            by_route[route_id] = evidence;
        }
        result = ProviderMetadata(provider=PROVIDER, status=SourceStatus.LIVE, fetched_at=live.fetched_at, expires_at=live.expires_at);
        if missing {
            result.warnings = [ProviderWarning(code="PARTIAL_WEATHER", message="Some points along these routes have no forecast yet or couldn't be read.")];
        }
        return ProviderResult(metadata=result, data=by_route);
    }
}

def unread(sample: RouteSample, code: str, message: str) -> WeatherEvidence {
    source = ProviderMetadata(provider=PROVIDER, status=SourceStatus.UNAVAILABLE, warnings=[ProviderWarning(code=code, message=message)]);
    return WeatherEvidence(place=sample.place, valid_from=sample.at.isoformat(), valid_until=(sample.at + timedelta(hours=1)).isoformat(), source=source);
}

"""The forecast hour covering the sample, and the alerts in force then."""
def sample_evidence(sample: RouteSample, reading: PointWeather | None, live: ProviderMetadata, horizon: datetime) -> WeatherEvidence {
    if sample.at > horizon { return unread(sample, "BEYOND_FORECAST", "Forecasts don't reach this hour yet."); }
    if reading is None or reading.periods is None { return unread(sample, "UNREACHABLE", "This point's forecast couldn't be read."); }
    try {
        for value in reading.periods {
            period = json_object(value);
            start = parse_timestamp(json_text(period.get("startTime")));
            end = parse_timestamp(json_text(period.get("endTime")));
            if not start <= sample.at < end { continue; }
            severity: RiskLevel = RiskLevel.UNKNOWN;
            names: list[str] = [];
            if reading.alerts is not None {
                severity = RiskLevel.LOW;
                for alert in reading.alerts {
                    if not alert_in_force(alert, sample.at) { continue; }
                    level = alert_level(alert);
                    names.append(str(alert.get("event") or "Weather alert"));
                    if level == RiskLevel.HIGH or (level == RiskLevel.MODERATE and severity == RiskLevel.LOW) { severity = level; }
                }
            }
            return WeatherEvidence(place=sample.place, valid_from=start.isoformat(), valid_until=end.isoformat(), source=live,
                precipitation_probability=chance(period.get("probabilityOfPrecipitation")), wind_kph=wind_kph(period.get("windSpeed")),
                alert_severity=severity, summary=str(period.get("shortForecast") or ""), alerts=list(dict.fromkeys(names)));
        }
    } except (ValueError, TypeError, KeyError) {
        return unread(sample, "UNREADABLE", "This point's forecast was malformed.");
    }
    return unread(sample, "NO_FORECAST_HOUR", "The forecast doesn't cover this hour.");
}
