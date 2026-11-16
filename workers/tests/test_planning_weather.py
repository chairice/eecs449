import copy
from datetime import datetime, timedelta, timezone

import pytest

from server import planning_weather as weather
from server import planning_api as api
from server.planning_core import blank_trip, validate_trip, dumps

STAMP = datetime(2026, 11, 15, 12, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def private_store(tmp_path, monkeypatch):
    monkeypatch.setenv("PLANNER_DATA_DIR", str(tmp_path))


def trip():
    value = blank_trip("trip_weather")
    value.update(startDate="2026-11-16", endDate="2026-11-17",
                 places=[{"id": "sf", "query": "San Francisco", "kind": "CITY", "lat": 37.7749, "lon": -122.4194, "timezone": "America/Los_Angeles"}],
                 days=[{"id": "day", "date": "2026-11-16", "title": "Explore", "overnightPlaceId": "sf", "items": []}])
    return validate_trip(value)


def sources(*, fail_forecast=False, fail_alerts=False, dates=("2026-11-16T00:00:00-08:00", "2026-11-17T00:00:00-08:00")):
    def fetch(url, ttl):
        if "/alerts/" in url:
            if fail_alerts: raise OSError("recorded outage")
            return {"features": [{"id": "https://api.weather.gov/alerts/warning1", "properties": {
                "event": "Winter Storm Warning", "headline": "Winter Storm Warning for the area", "description": "Heavy snow.",
                "instruction": "Avoid unnecessary travel.", "severity": "Severe", "onset": dates[0], "expires": dates[1], "status": "Actual"}}]}
        if "/points/" in url:
            return {"properties": {"forecastHourly": "https://api.weather.gov/gridpoints/MTR/85,105/forecast/hourly"}}
        if fail_forecast: raise OSError("recorded outage")
        return {"properties": {"periods": [{"startTime": dates[0], "endTime": dates[1], "shortForecast": "Rain", "temperature": 52,
                                             "temperatureUnit": "F", "windSpeed": "10 mph", "probabilityOfPrecipitation": {"value": 60}}]}}
    return fetch


def test_official_warning_survives_forecast_outage_with_full_instructions():
    sample = weather.samples_for(trip())[0]
    value = weather.read_sample(sample, sources(fail_forecast=True), STAMP)
    assert value["status"] == "READY" and value["severity"] == "HIGH"
    assert value["alerts"][0]["instruction"] == "Avoid unnecessary travel."
    assert value["temperature"] is None and value["summary"] == "Winter Storm Warning"


def test_alert_and_forecast_refresh_failure_retains_only_still_relevant_warning():
    sample = weather.samples_for(trip())[0]
    prior = weather.read_sample(sample, sources(), STAMP)
    value = weather.read_sample(sample, sources(fail_forecast=True, fail_alerts=True), STAMP, prior)
    assert value["alerts"] == prior["alerts"]
    late = weather.read_sample(sample, sources(fail_forecast=True, fail_alerts=True), STAMP + timedelta(days=5), prior)
    assert not late["alerts"]


def test_expired_or_unrelated_current_alerts_do_not_attach_to_future_travel():
    sample = weather.samples_for(trip())[0]
    value = weather.read_sample(sample, sources(dates=("2026-11-14T00:00:00Z", "2026-11-15T10:00:00Z")), STAMP)
    assert not value["alerts"]
    assert value["status"] == "FUTURE" and value["temperature"] is None


def test_future_forecast_is_quiet_and_no_conditions_are_invented():
    snapshot = trip(); snapshot["days"][0]["date"] = "2026-12-22"
    sample = weather.samples_for(snapshot)[0]
    value = weather.read_sample(sample, lambda url, ttl: {"features": []} if "/alerts/" in url else (_ for _ in ()).throw(AssertionError("must not invent long-range forecasts")), STAMP)
    assert value["status"] == "FUTURE" and value["temperature"] is None and not value["alerts"]


def test_flights_sample_only_airport_ground_endpoints_in_local_zones():
    snapshot = blank_trip("flight_weather")
    snapshot["places"] = [{"id": "dtw", "query": "DTW", "timezone": "America/Detroit", "lat": 42.2124, "lon": -83.3534},
                          {"id": "sfo", "query": "SFO", "timezone": "America/Los_Angeles", "lat": 37.6213, "lon": -122.379}]
    snapshot["legs"] = [{"id": "flight", "fromId": "dtw", "toId": "sfo", "mode": "FLIGHT", "departDate": "2026-11-16", "departTime": "09:00", "arriveDate": "2026-11-16", "arriveTime": "11:00"}]
    samples = weather.samples_for(validate_trip(snapshot))
    assert len(samples) == 2 and {s["role"] for s in samples} == {"DEPARTURE_GROUND", "ARRIVAL_GROUND"}
    assert samples[0]["start"] == "2026-11-16T14:00:00+00:00" and samples[1]["start"] == "2026-11-16T19:00:00+00:00"


@pytest.mark.parametrize("zone,day,hours", [("America/Phoenix", "2026-11-01", 24), ("America/Anchorage", "2026-11-01", 25), ("America/Detroit", "2026-03-08", 23)])
def test_day_windows_respect_arizona_alaska_and_dst(zone, day, hours):
    first,last = weather.local_window(day, "", "", zone)
    assert (last-first).total_seconds() == hours*3600


def test_long_plans_have_more_than_the_old_six_leg_limit():
    snapshot = trip()
    snapshot["stays"] = [{"id": "stay", "placeId": "sf", "checkIn": "2026-11-16", "checkOut": "2026-12-01"}]
    samples = weather.samples_for(validate_trip(snapshot))
    assert len([s for s in samples if s["role"] == "BASE"]) == 15


def test_weather_fingerprint_changes_only_for_weather_relevant_inputs_and_guest_import_preserves_cache():
    snapshot = trip(); initial = weather.weather_key(snapshot)
    renamed = copy.deepcopy(snapshot); renamed["title"] = "Another title"
    assert weather.weather_key(renamed) == initial
    changed = copy.deepcopy(snapshot); changed["days"][0]["date"] = "2026-11-17"
    assert weather.weather_key(changed) != initial
    changed = copy.deepcopy(snapshot); changed["places"][0]["lat"] += 1
    assert weather.weather_key(changed) != initial
    value = weather.refresh(snapshot, fetch=sources(), stamp=STAMP)
    imported = api.fresh(dumps({"snapshot": snapshot}))
    assert weather.cached_weather(imported["snapshot"])["fingerprint"] == value["fingerprint"]
    assert not weather.cached_weather(changed)  # A late old refresh cannot attach to changed inputs.


def test_source_url_validation_rejects_unrelated_or_private_sources():
    for url in ["http://api.weather.gov/points/1,2", "https://api.weather.gov.evil.com/grid", "https://localhost/", "https://127.0.0.1", "https://api.weather.gov:8000/grid"]:
        with pytest.raises(ValueError): weather.source_url(url)


def test_cached_background_request_returns_immediately_without_refetch(monkeypatch):
    snapshot = trip(); value = weather.refresh(snapshot, fetch=sources(), stamp=STAMP)
    def unexpected(*_): raise AssertionError("fresh cached forecast must not queue work")
    monkeypatch.setattr(weather._executor, "submit", unexpected)
    result = weather.loads(weather.weather_json(dumps({"snapshot": snapshot})))
    assert result["fingerprint"] == value["fingerprint"] and result["status"] == "READY"


def test_drive_samples_follow_cumulative_distance_instead_of_uniform_vertex_index():
    snapshot = blank_trip("drive_weather")
    snapshot["places"] = [{"id": "sf", "query": "San Francisco", "timezone": "America/Los_Angeles", "lat": 37.7, "lon": -122.4},
                          {"id": "la", "query": "Los Angeles", "timezone": "America/Los_Angeles", "lat": 34.0, "lon": -118.2}]
    snapshot["legs"] = [{"id": "drive", "fromId": "sf", "toId": "la", "mode": "DRIVE", "departDate": "2026-11-16", "departTime": "08:00", "arriveDate": "2026-11-16", "arriveTime": "14:00", "durationMinutes": 360}]
    # Many tiny early vertices must not bias every sample toward the origin.
    route = {"fromQuery": "San Francisco", "toQuery": "Los Angeles", "durationMinutes": 360,
             "points": [[37.7,-122.4], [37.699,-122.399], [37.698,-122.398], [34,-118.2]]}
    samples = weather.samples_for(validate_trip(snapshot), [route])
    interior = [s for s in samples if s["role"] == "DRIVE"]
    assert len(interior) == 4
    assert 34 < interior[-1]["lat"] < 35.5
    assert interior[0]["lat"] < 37.5
    assert all(s["timezone"] == "America/Los_Angeles" for s in interior)
    assert all(samples[0]["start"] < s["start"] < samples[1]["start"] for s in interior)


def test_long_valid_official_warning_is_preserved_beyond_forecast_horizon():
    snapshot = trip(); snapshot["days"][0]["date"] = "2026-12-01"
    sample = weather.samples_for(snapshot)[0]
    def fetch(url, ttl):
        assert "/alerts/" in url, "Do not invent an hourly forecast beyond its horizon"
        return sources(dates=("2026-11-15T00:00:00Z", "2026-12-10T00:00:00Z"))(url, ttl)
    result = weather.read_sample(sample, fetch, STAMP)
    assert result["status"] == "READY" and result["severity"] == "HIGH" and result["temperature"] is None


def test_cached_alert_expiry_is_enforced_while_background_refresh_is_pending():
    sample = weather.samples_for(trip())[0]
    prior = weather.read_sample(sample, sources(fail_forecast=True), STAMP)
    assert prior["alerts"]
    value = weather.visible_weather({"samples": [prior]}, STAMP + timedelta(days=3))
    assert not value["samples"][0]["alerts"]
    assert value["samples"][0]["summary"] != "Winter Storm Warning"
    assert value["status"] == "UNAVAILABLE"
