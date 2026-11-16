"""Usage: python3 scripts/build-corridor-fixtures.py web/fixtures/michigan-ohio-corridors.json

Author web/fixtures/michigan-ohio-corridors.json: synthetic schedules from
Ann Arbor to more cities. Bus paths come from public OSRM road geometry once,
at authoring time; train paths join real station locations in order."""
import json, sys, urllib.request

OUT = sys.argv[1]

PLACES = [
    ("ann-arbor", "Ann Arbor demo terminal", 42.2877, -83.7430, "America/Detroit"),
    ("detroit", "Detroit demo terminal", 42.3681, -83.0730, "America/Detroit"),
    ("lansing", "Lansing demo terminal", 42.7325, -84.5555, "America/Detroit"),
    ("grand-rapids", "Grand Rapids demo terminal", 42.9569, -85.6814, "America/Detroit"),
    ("kalamazoo", "Kalamazoo demo interchange", 42.2952, -85.5841, "America/Detroit"),
    ("toledo", "Toledo demo terminal", 41.6386, -83.5422, "America/New_York"),
    ("cleveland", "Cleveland demo terminal", 41.5061, -81.6995, "America/New_York"),
]
COORD = {p[0]: (p[2], p[3]) for p in PLACES}

CITIES = [
    ("ann-arbor", ["ann arbor", "ann arbor mi", "ann arbor michigan"]),
    ("detroit", ["detroit", "detroit mi", "detroit michigan"]),
    ("lansing", ["lansing", "lansing mi", "lansing michigan"]),
    ("grand-rapids", ["grand rapids", "grand rapids mi", "grand rapids michigan"]),
    ("toledo", ["toledo", "toledo oh", "toledo ohio"]),
    ("cleveland", ["cleveland", "cleveland oh", "cleveland ohio"]),
]

# Train alignments through real station locations, in order.
TRAIN_PATHS = {
    ("ann-arbor", "detroit"): [[42.2877, -83.743], [42.2445, -83.6136], [42.2469, -83.5146], [42.2817, -83.3863], [42.3070, -83.2350], [42.3226, -83.1731], [42.3480, -83.1180], [42.3681, -83.073]],
    ("toledo", "cleveland"): [[41.6386, -83.5422], [41.5800, -83.3500], [41.5070, -83.1460], [41.4520, -82.7130], [41.4220, -82.3640], [41.3670, -82.1080], [41.3900, -81.9300], [41.4500, -81.8100], [41.5061, -81.6995]],
}

BUS_PAIRS = [("ann-arbor", "detroit"), ("ann-arbor", "lansing"), ("ann-arbor", "grand-rapids"), ("kalamazoo", "grand-rapids"), ("ann-arbor", "toledo"), ("ann-arbor", "cleveland")]


def road(a, b):
    (alat, alon), (blat, blon) = COORD[a], COORD[b]
    url = f"https://router.project-osrm.org/route/v1/driving/{alon},{alat};{blon},{blat}?overview=simplified&geometries=geojson"
    import subprocess
    data = json.loads(subprocess.run(["curl", "-s", "-m", "30", "-A", "detour-fixture-author", url], check=True, capture_output=True, text=True).stdout)
    coords = data["routes"][0]["geometry"]["coordinates"]
    pts = [[round(lat, 4), round(lon, 4)] for lon, lat in coords]
    if len(pts) > 90:
        step = len(pts) / 88
        pts = [pts[0]] + [pts[int(i * step)] for i in range(1, 88)] + [pts[-1]]
    # Begin and end exactly on the terminals.
    pts[0] = [COORD[a][0], COORD[a][1]]
    pts[-1] = [COORD[b][0], COORD[b][1]]
    out = []
    for p in pts:
        if not out or out[-1] != p:
            out.append(p)
    return out


def leg(lid, mode, o, d, dep, arr, operator, service):
    return {"id": lid, "mode": mode, "origin_id": o, "destination_id": d, "departure_time": dep, "arrival_time": arr,
            "departure_day_offset": 0, "arrival_day_offset": 0, "operator": operator, "service": service}


R, C = "Demo Rail", "Demo Coach"
ROUTES = [
    # Detroit
    ("demo-dtw-train", 1500, [leg("dtw-train-1", "TRAIN", "ann-arbor", "detroit", "07:40", "08:35", R, "Synthetic train J")]),
    ("demo-dtw-bus", 1200, [leg("dtw-bus-1", "BUS", "ann-arbor", "detroit", "09:15", "10:20", C, "Synthetic bus K")]),
    ("demo-dtw-train-evening", 1700, [leg("dtw-train-2", "TRAIN", "ann-arbor", "detroit", "17:45", "18:40", R, "Synthetic train L")]),
    ("demo-dtw-return-train", 1500, [leg("dtw-return-train-1", "TRAIN", "detroit", "ann-arbor", "16:30", "17:25", R, "Synthetic train M")]),
    ("demo-dtw-return-bus", 1200, [leg("dtw-return-bus-1", "BUS", "detroit", "ann-arbor", "18:10", "19:20", C, "Synthetic bus N")]),
    # Lansing
    ("demo-lan-bus", 1800, [leg("lan-bus-1", "BUS", "ann-arbor", "lansing", "08:30", "09:55", C, "Synthetic bus P")]),
    ("demo-lan-bus-evening", 2000, [leg("lan-bus-2", "BUS", "ann-arbor", "lansing", "16:45", "18:15", C, "Synthetic bus Q")]),
    ("demo-lan-return-bus", 1800, [leg("lan-return-bus-1", "BUS", "lansing", "ann-arbor", "15:00", "16:30", C, "Synthetic bus R")]),
    # Grand Rapids
    ("demo-grr-bus", 3200, [leg("grr-bus-1", "BUS", "ann-arbor", "grand-rapids", "10:00", "12:40", C, "Synthetic bus S")]),
    ("demo-grr-train-bus", 3900, [leg("grr-connection-train", "TRAIN", "ann-arbor", "kalamazoo", "08:10", "10:20", R, "Synthetic train T"),
                                   leg("grr-connection-bus", "BUS", "kalamazoo", "grand-rapids", "11:05", "12:15", C, "Synthetic bus U")]),
    ("demo-grr-return-bus", 3200, [leg("grr-return-bus-1", "BUS", "grand-rapids", "ann-arbor", "14:30", "17:15", C, "Synthetic bus V")]),
    ("demo-grr-return-transfer", 3900, [leg("grr-return-connection-bus", "BUS", "grand-rapids", "kalamazoo", "13:00", "14:10", C, "Synthetic bus W"),
                                         leg("grr-return-connection-train", "TRAIN", "kalamazoo", "ann-arbor", "14:55", "17:05", R, "Synthetic train X")]),
    # Toledo
    ("demo-tol-bus", 1600, [leg("tol-bus-1", "BUS", "ann-arbor", "toledo", "09:00", "10:15", C, "Synthetic bus Y")]),
    ("demo-tol-bus-evening", 1900, [leg("tol-bus-2", "BUS", "ann-arbor", "toledo", "17:30", "18:50", C, "Synthetic bus Z")]),
    ("demo-tol-return-bus", 1600, [leg("tol-return-bus-1", "BUS", "toledo", "ann-arbor", "15:30", "16:45", C, "Synthetic bus AA")]),
    # Cleveland
    ("demo-cle-bus", 3600, [leg("cle-bus-1", "BUS", "ann-arbor", "cleveland", "08:00", "11:50", C, "Synthetic bus AB")]),
    ("demo-cle-bus-train", 4400, [leg("cle-connection-bus", "BUS", "ann-arbor", "toledo", "11:00", "12:15", C, "Synthetic bus AC"),
                                   leg("cle-connection-train", "TRAIN", "toledo", "cleveland", "13:05", "15:45", R, "Synthetic train AD")]),
    ("demo-cle-return-bus", 3600, [leg("cle-return-bus-1", "BUS", "cleveland", "ann-arbor", "14:00", "17:50", C, "Synthetic bus AE")]),
    ("demo-cle-return-transfer", 4400, [leg("cle-return-connection-train", "TRAIN", "cleveland", "toledo", "12:20", "15:00", R, "Synthetic train AF"),
                                         leg("cle-return-connection-bus", "BUS", "toledo", "ann-arbor", "15:45", "17:00", C, "Synthetic bus AG")]),
]

paths = [{"mode": "TRAIN", "between": list(k), "points": v} for k, v in TRAIN_PATHS.items()]
paths += [{"mode": "BUS", "between": [a, b], "points": road(a, b)} for a, b in BUS_PAIRS]

payload = {
    "schema_version": 1,
    "synthetic": True,
    "description": "Entirely synthetic daily demo templates from Ann Arbor to more Michigan and Ohio cities, not real timetables, fares or bookings. Local leg times repeat on the requested calendar date. Bus paths trace real road routes (OSRM, authored once); train paths join real station locations in order and are approximate alignments, not timetabled service.",
    "source": {
        "provider": "detour-synthetic-corridor-v1",
        "status": "FIXTURE",
        "fetched_at": "2026-11-07T00:00:00Z",
        "expires_at": None,
        "warnings": [
            {"code": "FIXTURE_AUTHORED_AT", "message": "fetched_at records when this synthetic dataset was authored, not a live observation."},
            {"code": "NO_REALTIME_DATA", "message": "No cancellation, delay, weather or seat-availability information is available."},
        ],
    },
    "cities": [{"place_id": pid, "names": names} for pid, names in CITIES],
    "places": [{"id": i, "name": n, "latitude": la, "longitude": lo, "timezone": tz} for i, n, la, lo, tz in PLACES],
    "routes": [{"id": rid, "price_cents": price, "currency": "USD", "legs": legs} for rid, price, legs in ROUTES],
    "paths": paths,
}

with open(OUT, "w") as f:
    f.write("{\n")
    keys = list(payload)
    for ki, k in enumerate(keys):
        v = payload[k]
        tail = "," if ki < len(keys) - 1 else ""
        if isinstance(v, list):
            f.write(f'  "{k}": [\n')
            for i, item in enumerate(v):
                f.write("    " + json.dumps(item, ensure_ascii=False) + ("," if i < len(v) - 1 else "") + "\n")
            f.write(f"  ]{tail}\n")
        elif isinstance(v, dict):
            body = json.dumps(v, indent=2, ensure_ascii=False).replace("\n", "\n  ")
            f.write(f'  "{k}": {body}{tail}\n')
        else:
            f.write(f'  "{k}": {json.dumps(v)}{tail}\n')
    f.write("}\n")
print("wrote", OUT, len(ROUTES), "routes", [len(p["points"]) for p in paths])
