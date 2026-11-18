"""Cached free geocoding. Unresolved locations remain unresolved on the map."""
import copy
import gzip
import json
import math
import threading
import os
import re
import time
from functools import lru_cache
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import urlencode

from server.planning_jobs import connection

_last = 0.0
_request_lock = threading.Lock()


@lru_cache(maxsize=1)
def catalog():
    with gzip.open(Path(__file__).resolve().parents[2] / "web/fixtures/atlas/places.json.gz", "rt") as handle:
        return json.load(handle)



@lru_cache(maxsize=1)
def states():
    with open(Path(__file__).resolve().parents[2] / "web/fixtures/atlas/states.geojson") as handle:
        return sorted([feature["properties"] for feature in json.load(handle)["features"]], key=lambda value: len(value["name"]), reverse=True)


@lru_cache(maxsize=1)
def zone_finder():
    from timezonefinder import TimezoneFinder
    return TimezoneFinder()


def normalized_name(value):
    value = re.sub(r"\s*\([^)]*\)", "", value)
    value = re.sub(r"\bscenic overlook\b", "", value, flags=re.I)
    words = re.findall(r"[a-z0-9]+", value.casefold())
    return " ".join("center" if word == "centre" else word for word in words if word != "the")


def select_feature(features, target, expected_state=""):
    candidates = []
    for feature in features:
        props = feature.get("properties", {})
        coordinates = feature.get("geometry", {}).get("coordinates", [])
        if props.get("countrycode", "").upper() != "US" or len(coordinates) != 2:
            continue
        if any(type(value) not in {int, float} or not math.isfinite(value) for value in coordinates):
            continue
        if abs(coordinates[0]) > 180 or abs(coordinates[1]) > 90:
            continue
        if expected_state and props.get("state", "").casefold() != expected_state.casefold():
            continue
        # Exact entity names prevent Bell Rock from becoming a nearby hotel.
        if normalized_name(props.get("name", "")) == normalized_name(target):
            candidates.append(feature)
    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        first_lon, first_lat = candidates[0]["geometry"]["coordinates"]
        distances = [math.hypot(((((f["geometry"]["coordinates"][0] - first_lon) + 180) % 360) - 180) * math.cos(math.radians(first_lat)), f["geometry"]["coordinates"][1] - first_lat) * 111000 for f in candidates]
        # OSM often has a node and a way for the same visitor center/viewpoint.
        # Distinct, distant namesakes remain unresolved.
        if max(distances) <= 250:
            return candidates[0]
    return None


def photon(query):
    global _last
    with _request_lock:
        slot = max(time.monotonic(), _last + 1.1)
        _last = slot
    time.sleep(max(0, slot - time.monotonic()))
    endpoint = os.getenv("PLANNER_GEOCODER_URL", "https://photon.komoot.io/api/")
    url = endpoint + "?" + urlencode({"q": query, "limit": 10, "lang": "en"})
    request = Request(url, headers={"User-Agent": "AtlasTripStudio/0.1 (interactive US trip planning)"})
    with urlopen(request, timeout=9) as response:
        return json.load(response).get("features", [])


def resolve(query, kind):
    cache_key = "v3:" + kind + ":" + query.casefold()
    with connection() as db:
        db.execute("CREATE TABLE IF NOT EXISTS geocodes (query TEXT PRIMARY KEY, value TEXT, updated REAL)")
        row = db.execute("SELECT * FROM geocodes WHERE query=?", (cache_key,)).fetchone()
        if row and row["updated"] > time.time() - (86400 * 180 if row["value"] != "null" else 3600):
            return json.loads(row["value"])
    local = []
    q = re.sub(r",\s*(?:usa|united states)$", "", query.casefold().strip())
    for props in states():
        match = re.fullmatch(r"(.+?)(?:,\s*|\s+)" + re.escape(props["name"].casefold()), q)
        if match:
            q = match.group(1).rstrip(", ") + ", " + props["code"].casefold()
            break
    for place in catalog():
        if kind == "AIRPORT" and place["kind"] != "AIRPORT": continue
        if kind == "CITY" and place["kind"] != "CITY": continue
        if kind in {"PARK", "PROPERTY"}: continue
        matches = {place["name"].casefold() + ", " + place["state"].casefold(), place["name"].casefold() + " " + place["state"].casefold()}
        if place["kind"] == "AIRPORT":
            matches.update(alias.casefold() for alias in [place["code"], *place["aliases"]] if alias)
        if q in matches or (kind == "AIRPORT" and place["code"] and re.search(r"(?<![A-Za-z])" + re.escape(place["code"]) + r"(?![A-Za-z])", query)) or (kind == "CITY" and q == place["name"].casefold()):
            local.append(place)
    result = None
    if len(local) == 1:
        value = local[0]
        result = {"lat": value["lat"], "lon": value["lon"], "sourceUrl": "https://www.geonames.org/" if value["kind"] == "CITY" else "https://ourairports.com/"}
    else:
        expected = next((state["name"] for state in states() if q.endswith(", " + state["code"].casefold()) or q.endswith(" " + state["code"].casefold())), "")
        target = query.split(",")[0].strip()
        candidates = []
        try:
            candidates = photon(query)
            value = select_feature(candidates, target, expected)
            if value is None:
                short_query = normalized_name(target) + (" " + expected if expected else "")
                if short_query.casefold() != query.casefold():
                    candidates = photon(short_query)
                    value = select_feature(candidates, target, expected)
            if value:
                lon, lat = value["geometry"]["coordinates"]
                props = value["properties"]
                result = {"address": ", ".join(str(props[k]) for k in ["housenumber", "street", "city", "state", "postcode"] if props.get(k)), "lat": lat, "lon": lon, "sourceUrl": "https://www.openstreetmap.org/" + {"N": "node", "W": "way", "R": "relation"}.get(props.get("osm_type"), "node") + "/" + str(props.get("osm_id", ""))}
        except Exception:
            pass
    if result:
        try:
            result["timezone"] = zone_finder().timezone_at(lat=result["lat"], lng=result["lon"]) or ""
        except Exception:
            result["timezone"] = ""
    with connection() as db:
        db.execute("INSERT OR REPLACE INTO geocodes VALUES(?,?,?)", (cache_key, json.dumps(result), time.time()))
    return result


def enrich(snapshot, update, maximum=35, seconds=90, kinds=None):
    snapshot = copy.deepcopy(snapshot)
    started = time.monotonic()
    lookups = 0
    for place in snapshot["places"]:
        if place.get("lat") is not None or (kinds and place["kind"] not in kinds):
            continue
        if time.monotonic() - started > seconds or lookups >= maximum:
            break
        update("Locating " + place["label"])
        found = resolve(place["query"], place["kind"])
        if not found and place["kind"] == "AIRPORT":
            found = resolve(place["label"], place["kind"])
        lookups += 1
        if found:
            place.update(found)
    # Photos enrich already located places too, so old saved trips can gain imagery.
    # A bounded pool limits serial network latency and failed images never reject a plan.
    from concurrent.futures import ThreadPoolExecutor, wait
    from .place_photos import resolve_photo
    targets = [place for place in snapshot["places"] if place.get("lat") is not None and not place.get("photoUrl") and place.get("kind") != "AIRPORT"][:8]
    if targets and time.monotonic() - started < seconds:
        update("Finding place photographs")
        pool = ThreadPoolExecutor(max_workers=4)
        futures = {pool.submit(resolve_photo, place): place for place in targets}
        done, pending = wait(futures, timeout=min(7, max(0, seconds - (time.monotonic() - started))))
        for future in done:
            try:
                photo = future.result()
                if photo: futures[future].update(photo)
            except Exception:
                pass
        for future in pending: future.cancel()
        pool.shutdown(wait=False, cancel_futures=True)
    return snapshot
