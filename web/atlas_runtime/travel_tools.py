"""Free sourced road estimates and calculated daylight, separate from inventory."""
import json
import os
import time
from datetime import date
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from server.planning_core import PlanningError, calendar, uid
from server.planning_jobs import connection
from .geography import resolve


def driving(args):
    first = resolve(args["fromQuery"], "PLACE")
    last = resolve(args["toQuery"], "PLACE")
    if not first or not last:
        raise PlanningError("An endpoint could not be located unambiguously; the road route remains unchecked.")
    coordinates = f"{first['lon']},{first['lat']};{last['lon']},{last['lat']}"
    url = os.getenv("PLANNER_ROUTER_URL", "https://router.project-osrm.org") + "/route/v1/driving/" + coordinates + "?overview=full&geometries=geojson"
    with connection() as db:
        db.execute("CREATE TABLE IF NOT EXISTS road_routes (query TEXT PRIMARY KEY, value TEXT, updated REAL)")
        cached = db.execute("SELECT * FROM road_routes WHERE query=?", (coordinates,)).fetchone()
    if cached and cached["updated"] > time.time() - 86400:
        return json.loads(cached["value"])
    request = Request(url, headers={"User-Agent": "AtlasTripStudio/0.1"})
    with urlopen(request, timeout=20) as response:
        payload = json.load(response)
    if payload.get("code") != "Ok" or not payload.get("routes"):
        raise PlanningError("The public router could not calculate this drive.")
    route = payload["routes"][0]
    if route["distance"] > 10000000:
        raise PlanningError("This calculated road route needs review before use.")
    result = {"id": uid("road"), "kind": "ROAD", "fromQuery": args["fromQuery"], "toQuery": args["toQuery"],
        "from": first, "to": last, "sourceUrl": url, "observedAt": time.time(), "provider": "OSRM",
        "durationMinutes": round(route["duration"] / 60), "distanceMeters": round(route["distance"]),
        "points": [[lat, lon] for lon, lat in route["geometry"]["coordinates"]],
        "note": "Road estimate; excludes stops, current traffic, weather and seasonal closures."}
    with connection() as db:
        db.execute("INSERT OR REPLACE INTO road_routes VALUES(?,?,?)", (coordinates, json.dumps(result), time.time()))
    return result


def daylight(args):
    from astral import Observer
    from astral.sun import dawn, dusk, noon, sunrise, sunset
    place = resolve(args["query"], "PLACE")
    if not place:
        raise PlanningError("This location could not be resolved for a daylight calculation.")
    target = date.fromisoformat(calendar(args["date"], "daylight date"))
    if not place.get("timezone") and not args.get("timezone"):
        raise PlanningError("The location's time zone could not be verified for daylight calculation.")
    zone = ZoneInfo(place.get("timezone") or args["timezone"])
    observer = Observer(latitude=place["lat"], longitude=place["lon"])
    times, unavailable = {}, {}
    events = [("dawn", dawn, {"depression": 6}), ("sunrise", sunrise, {}), ("noon", noon, {}),
              ("sunset", sunset, {}), ("dusk", dusk, {"depression": 6}),
              ("nauticalDawn", dawn, {"depression": 12}), ("nauticalDusk", dusk, {"depression": 12}),
              ("astronomicalDawn", dawn, {"depression": 18}), ("astronomicalDusk", dusk, {"depression": 18})]
    # A missing twilight event must not erase real sunrise/sunset times in Alaska.
    for name, calculate, options in events:
        try:
            times[name] = calculate(observer, date=target, tzinfo=zone, **options).isoformat()
        except ValueError as exc:
            unavailable[name] = str(exc)
    return {"id": uid("sun"), "kind": "DAYLIGHT", "date": target.isoformat(), "location": place, "timezone": str(zone),
            "times": times, "unavailableEvents": unavailable, "provider": "Astral 3.2",
            "sourceUrl": "https://astral.readthedocs.io/en/latest/package.html#module-astral.sun",
            "note": "Calculated astronomical times; nearby terrain may obstruct the horizon. Missing events do not occur on this date at this latitude."}


def check_schedule(snapshot, known_sources):
    """Check temporal structure without pretending to verify opening hours."""
    warnings = []
    for day in snapshot["days"]:
        end = None
        for item in day["items"]:
            if not item["locked"] and item["timingState"] == "CHECKED" and not item["sourceRefs"]:
                item["timingState"] = "PROVISIONAL"
            if not item["locked"] and item["timingState"] == "CHECKED" and any(ref not in known_sources for ref in item["sourceRefs"]):
                item["timingState"] = "PROVISIONAL"
            start = item["startTime"]
            if start and end and start < end:
                if not item["locked"]:
                    item["timingState"] = "CONFLICT"
                warnings.append(f"{day['date']} · {item['title']}: overlaps the preceding activity. Review the timing.")
            if item["endTime"]:
                end = item["endTime"]
    return warnings
