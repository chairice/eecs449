"""Real NWS forecasts and alerts, fetched independently of trip transactions.

The public API returns immediately. Bounded background work writes private,
input-addressed cache files, so an older itinerary cannot overwrite a new one.
No synthetic weather is used when an official source is unavailable.
"""
from __future__ import annotations

import copy
import json
import math
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from server.planning_core import fingerprint, now, validate_trip, loads, dumps
from server.planning_jobs import data_dir

_executor = ThreadPoolExecutor(max_workers=3, thread_name_prefix="detour-weather")
_samples_executor = ThreadPoolExecutor(max_workers=6, thread_name_prefix="detour-nws")
_source_locks = {}
_lock = threading.RLock()
_pending = set()
_source_cache = {}
TTL = 300


def source_url(url):
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "api.weather.gov" or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError("NWS returned an unexpected source address")
    return url


def _fetch(url, ttl):
    url = source_url(url)
    with _lock:
        saved = _source_cache.get(url)
        if saved and saved[0] > time.time(): return copy.deepcopy(saved[1])
    contact = os.getenv("DETOUR_NWS_CONTACT", "interactive-us-trip-planner")
    request = Request(url, headers={"User-Agent": "Detour/1.0 (" + contact + ")", "Accept": "application/geo+json"})
    # Coalesce nearby activity/day samples hitting the same official endpoint.
    with _lock: gate = _source_locks.setdefault(url, threading.Lock())
    with gate:
        with _lock:
            saved = _source_cache.get(url)
            if saved and saved[0] > time.time(): return copy.deepcopy(saved[1])
        with urlopen(request, timeout=4) as response:
            source_url(response.url)
            raw = response.read(4_000_001)
            if len(raw) > 4_000_000: raise ValueError("NWS response exceeds source limit")
            value = json.loads(raw)
    with _lock:
        if len(_source_cache) > 512: _source_cache.clear()
        _source_cache[url] = (time.time() + ttl, value)
    return value


def moment(value):
    if not value: return None
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return result if result.tzinfo else result.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError): return None


def local_window(day, start, end, zone):
    try: tz = ZoneInfo(zone)
    except (ZoneInfoNotFoundError, ValueError): return None
    if not day: return None
    first = datetime.fromisoformat(day + "T" + (start or "00:00")).replace(tzinfo=tz)
    last = datetime.fromisoformat(day + "T" + end).replace(tzinfo=tz) if end else first + (timedelta(hours=2) if start else timedelta(days=1))
    if last <= first: last = first + timedelta(hours=1)
    return first.astimezone(timezone.utc), last.astimezone(timezone.utc)


def samples_for(snapshot, routes=()):
    places = {p["id"]: p for p in snapshot["places"]}
    samples = []
    seen = set()
    def add(target, place_id, day, start="", end="", role="PLACE", point=None):
        place = places.get(place_id, {})
        key = (target, place_id, day, start, role)
        if key in seen or len(samples) >= 96: return
        seen.add(key)
        lat, lon = point if point else (place.get("lat"), place.get("lon"))
        window = local_window(day, start, end, place.get("timezone") or snapshot["timezone"])
        samples.append({"id": fingerprint(key)[:24], "targetId": target, "placeId": place_id,
                       "label": place.get("label", "Along your drive"), "date": day, "role": role,
                       "lat": lat, "lon": lon, "timezone": place.get("timezone") or snapshot["timezone"],
                       "start": window[0].isoformat() if window else "", "end": window[1].isoformat() if window else ""})
    for leg in snapshot["legs"]:
        flight = leg["mode"] == "FLIGHT"
        add(leg["id"], leg["fromId"], leg["departDate"], leg["departTime"], role="DEPARTURE_GROUND" if flight else "DEPARTURE")
        add(leg["id"], leg["toId"], leg["arriveDate"] or leg["departDate"], leg["arriveTime"], role="ARRIVAL_GROUND" if flight else "ARRIVAL")
        if leg["mode"] == "DRIVE":
            source = next((r for r in routes if r.get("fromQuery") == places[leg["fromId"]]["query"] and r.get("toQuery") == places[leg["toId"]]["query"]), None)
            if source and source.get("points") and leg["departDate"] and leg["departTime"]:
                points = source["points"]
                lengths = [0.0]
                for a,b in zip(points, points[1:]):
                    lengths.append(lengths[-1] + math.hypot((b[1]-a[1])*math.cos(math.radians(a[0])), b[0]-a[0]))
                total = lengths[-1]
                duration = source.get("durationMinutes") or leg.get("durationMinutes")
                if total and duration:
                    first = local_window(leg["departDate"], leg["departTime"], "", places[leg["fromId"]].get("timezone") or snapshot["timezone"])[0]
                    for index in range(1, min(5, math.ceil(duration / 60))):
                        fraction = index / min(5, math.ceil(duration / 60))
                        distance = fraction * total
                        position = next((i for i,x in enumerate(lengths) if x >= distance), len(points)-1)
                        previous_position = max(0, position - 1)
                        segment = lengths[position] - lengths[previous_position]
                        along = (distance - lengths[previous_position]) / segment if segment else 0
                        lat = points[previous_position][0] + along * (points[position][0] - points[previous_position][0])
                        lon = points[previous_position][1] + along * (points[position][1] - points[previous_position][1])
                        try:
                            from timezonefinder import TimezoneFinder
                            zone = TimezoneFinder().timezone_at(lat=lat, lng=lon) or snapshot["timezone"]
                        except ImportError: zone = snapshot["timezone"]
                        at = (first + timedelta(minutes=duration*fraction)).astimezone(ZoneInfo(zone))
                        synthetic_id = "route-" + leg["id"] + "-" + str(index)
                        places[synthetic_id] = {"label": "Along your drive", "timezone": zone}
                        add(leg["id"], synthetic_id, at.date().isoformat(), at.strftime("%H:%M"), role="DRIVE", point=(lat,lon))
    for stay in snapshot["stays"]:
        if stay["checkIn"] and stay["checkOut"]:
            first = datetime.fromisoformat(stay["checkIn"])
            count = min(31, (datetime.fromisoformat(stay["checkOut"]) - first).days)
            for n in range(count): add(stay["id"], stay["placeId"], (first + timedelta(days=n)).date().isoformat(), role="BASE")
    for day in snapshot["days"]:
        if day["overnightPlaceId"]: add(day["id"], day["overnightPlaceId"], day["date"], role="DAY")
        for item in day["items"]:
            if item["placeId"]: add(item["id"], item["placeId"], day["date"], item["startTime"], item["endTime"], "ACTIVITY")
    return samples


def weather_key(snapshot, routes=()):
    return fingerprint({"tripId": snapshot["id"], "samples": samples_for(snapshot, routes)})


def _cache_path(key):
    folder = data_dir() / "weather"
    folder.mkdir(exist_ok=True, mode=0o700)
    return folder / (key + ".json")


def visible_weather(value, stamp=None):
    """Expire warnings even while a cached result is awaiting network refresh."""
    stamp = stamp or datetime.now(timezone.utc)
    value = copy.deepcopy(value)
    for sample in value.get("samples", []):
        start, end = moment(sample.get("start")), moment(sample.get("end"))
        prior = sample.get("alerts", [])
        current = [a for a in prior if moment(a.get("onset")) and moment(a.get("expires")) and start and end
                   and moment(a["onset"]) < end and moment(a["expires"]) > max(stamp, start)]
        sample["alerts"] = current
        if prior and not current:
            sample["summary"] = sample.get("forecastSummary") or "Weather will be checked closer to departure."
            sample["severity"] = sample.get("forecastSeverity", "UNKNOWN")
            sample["status"] = "READY" if sample.get("forecastAvailable") else "FUTURE" if start and start > stamp + timedelta(days=7) else "UNAVAILABLE"
        elif current:
            sample["summary"] = current[0]["event"]
            sample["severity"] = "HIGH" if any(a["severity"] in {"Severe", "Extreme"} or a["event"].lower().endswith("warning") for a in current) else "MODERATE"
    samples = value.get("samples", [])
    value["status"] = "READY" if any(s["status"] == "READY" for s in samples) else "FUTURE" if samples and all(s["status"] == "FUTURE" for s in samples) else "UNAVAILABLE"
    return value


def _read(key):
    try: return visible_weather(json.loads(_cache_path(key).read_text()))
    except (OSError, ValueError): return None


def _write(key, value):
    path = _cache_path(key)
    temp = path.with_suffix(".tmp")
    descriptor = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle: json.dump(value, handle, allow_nan=False)
    temp.replace(path)


def relevant_alerts(features, start, end, stamp):
    result = []
    for feature in features:
        p = feature.get("properties", {})
        onset = moment(p.get("onset") or p.get("effective") or p.get("sent"))
        expires = moment(p.get("ends") or p.get("expires"))
        if not onset or not expires or expires <= stamp or onset >= end or expires <= start: continue
        if p.get("status") not in (None, "Actual") or p.get("messageType") == "Cancel": continue
        url = feature.get("id") or p.get("@id") or ""
        try: source_url(url)
        except ValueError: url = "https://www.weather.gov/"
        result.append({"id": p.get("id") or feature.get("id") or fingerprint(p), "event": p.get("event", "Weather alert"),
                       "headline": p.get("headline", ""), "description": p.get("description", ""), "instruction": p.get("instruction") or "",
                       "severity": p.get("severity", "Unknown"), "onset": onset.isoformat(), "expires": expires.isoformat(), "url": url})
    return result


def read_sample(sample, fetch=_fetch, stamp=None, previous=None):
    stamp = stamp or datetime.now(timezone.utc)
    value = {**sample, "status": "UNAVAILABLE", "summary": "Weather will be checked closer to departure.", "temperature": None,
             "temperatureUnit": "", "precipitation": None, "wind": "", "alerts": [], "severity": "UNKNOWN", "sourceUrl": "https://www.weather.gov/", "checkedAt": now()}
    start, end = moment(sample["start"]), moment(sample["end"])
    if not start or not end or sample["lat"] is None or sample["lon"] is None: return value
    future = start > stamp + timedelta(days=7)
    if end <= stamp:
        value["summary"] = "Forecasts are available for upcoming travel."
        return value
    point = f'{sample["lat"]:.4f},{sample["lon"]:.4f}'
    alerts_ok = False
    try:
        features = fetch("https://api.weather.gov/alerts/active?point=" + point, 300).get("features", [])
        value["alerts"] = relevant_alerts(features, start, end, stamp)
        alerts_ok = True
    except Exception:
        # A failed refresh cannot erase a still-valid official warning.
        if previous:
            value["alerts"] = [a for a in previous.get("alerts", []) if moment(a.get("expires")) and moment(a["expires"]) > max(stamp, start) and moment(a["onset"]) < end]
    if future:
        value["status"] = "READY" if value["alerts"] else "FUTURE"
        if value["alerts"]:
            value["summary"] = value["alerts"][0]["event"]
            value["severity"] = "HIGH" if any(a["severity"] in {"Severe", "Extreme"} or a["event"].lower().endswith("warning") for a in value["alerts"]) else "MODERATE"
        return value
    hourly_url = ""
    try:
        grid = fetch("https://api.weather.gov/points/" + point, 86400)
        hourly_url = source_url(grid["properties"]["forecastHourly"])
        periods = fetch(hourly_url, 900).get("properties", {}).get("periods", [])
        matching = [p for p in periods if moment(p.get("startTime")) and moment(p.get("endTime")) and moment(p["startTime"]) < end and moment(p["endTime"]) > start]
        if matching:
            middle = matching[len(matching)//2]
            value.update(status="READY", summary=middle.get("shortForecast", ""), temperature=middle.get("temperature"),
                         temperatureUnit=middle.get("temperatureUnit", ""), precipitation=max((p.get("probabilityOfPrecipitation", {}).get("value") or 0 for p in matching)),
                         wind=middle.get("windSpeed", ""), sourceUrl=hourly_url)
            value["forecastAvailable"] = True
            value["alertsAvailable"] = alerts_ok
        elif start > stamp:
            value["status"] = "FUTURE"
    except Exception: pass
    if value.get("forecastAvailable") and alerts_ok: value["severity"] = "LOW"
    if value.get("forecastAvailable"):
        import re
        speeds = [int(x) for x in re.findall(r"\d+", value["wind"])]
        max_speed = max(speeds, default=0)
        windy = max_speed >= (35 if "mph" in value["wind"].lower() else 56)
        icy = any(word in value["summary"].lower() for word in ["snow", "ice", "freezing", "thunderstorm"])
        if windy or (icy and (value["precipitation"] or 0) >= 50): value["severity"] = "MODERATE"
    value["forecastSummary"] = value["summary"] if value.get("forecastAvailable") else ""
    value["forecastSeverity"] = value["severity"]
    for alert in value["alerts"]:
        event = alert["event"].lower()
        if alert["severity"] in {"Severe", "Extreme"} or event.endswith("warning"):
            value["severity"] = "HIGH"
            break
        if alert["severity"] == "Moderate" or any(word in event for word in ["watch", "advisory"]): value["severity"] = "MODERATE"
    if value["alerts"]:
        value["status"] = "READY"
        value["summary"] = value["alerts"][0]["event"]
    return value


def refresh(snapshot, routes=(), fetch=_fetch, stamp=None):
    key = weather_key(snapshot, routes)
    previous = _read(key) or {}
    old = {s["id"]: s for s in previous.get("samples", [])}
    samples = samples_for(snapshot, routes)
    futures = {_samples_executor.submit(read_sample, s, fetch, stamp, old.get(s["id"])): s for s in samples}
    completed = {}
    try:
        for future in as_completed(futures, timeout=14):
            sample = futures[future]
            try: completed[sample["id"]] = future.result()
            except Exception: pass
    except TimeoutError: pass
    result = []
    def offline_fetch(*_): raise OSError("Weather response budget exceeded")
    for future, sample in futures.items():
        future.cancel()
        result.append(completed.get(sample["id"]) or read_sample(sample, offline_fetch, stamp, old.get(sample["id"])))
    status = "READY" if any(s["status"] == "READY" for s in result) else "FUTURE" if result and all(s["status"] == "FUTURE" for s in result) else "UNAVAILABLE"
    value = {"fingerprint": key, "status": status, "samples": result, "checkedAt": now(), "cachedAt": time.time()}
    _write(key, value)
    return value


def cached_weather(snapshot, routes=()):
    return _read(weather_key(snapshot, routes)) or {}


def weather_json(state_json: str) -> str:
    state = loads(state_json)
    snapshot = validate_trip(state["snapshot"])
    routes = state.get("routes", [])
    key = weather_key(snapshot, routes)
    cached = _read(key)
    if cached and cached.get("cachedAt", 0) > time.time() - TTL: return dumps(cached)
    def work():
        try: refresh(snapshot, routes)
        finally:
            with _lock: _pending.discard(key)
    with _lock:
        if key not in _pending and len(_pending) < 12:
            _pending.add(key)
            _executor.submit(work)
    if cached: return dumps({**cached, "refreshing": True})
    return dumps({"fingerprint": key, "status": "LOADING", "samples": [], "checkedAt": ""})
