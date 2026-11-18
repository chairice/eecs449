"""Auxiliary place imagery: immediate cached reads, bounded background retrieval.

No model call, graph write, revision or Undo mutation occurs here. The caller's
normal account ownership check precedes this helper; guests supply device state.
Only hardcoded public Wikimedia endpoints are contacted in background threads.
"""
from __future__ import annotations
import threading
from concurrent.futures import ThreadPoolExecutor
from server.planning_core import dumps, fingerprint, loads, validate_trip
from server.place_photos import resolve_photo
from server.planning_jobs import connection

_pool = ThreadPoolExecutor(max_workers=3, thread_name_prefix='detour-photos')
_lock = threading.Lock()
_pending = set()


def _key(place):
    return 'v1:' + place['query'].casefold() + ':' + str(round(place['lat'], 3)) + ':' + str(round(place['lon'], 3))


def _fetch(place, key):
    try: resolve_photo(place)
    finally:
        with _lock: _pending.discard(key)


def media_json(state_json: str) -> str:
    state = loads(state_json)
    snapshot = validate_trip(state['snapshot'])
    candidates = [p for p in snapshot['places'] if p.get('lat') is not None and p.get('kind') != 'AIRPORT'][:24]
    locations, awaiting = [], False
    with connection() as db:
        db.execute('CREATE TABLE IF NOT EXISTS place_photos (query TEXT PRIMARY KEY, value TEXT, updated REAL)')
        for place in candidates:
            key = _key(place)
            row = db.execute('SELECT * FROM place_photos WHERE query=?', (key,)).fetchone()
            import time, json
            fresh = row and row['updated'] > time.time() - (86400 * 30 if row['value'] != 'null' else 86400)
            if fresh:
                value = json.loads(row['value'])
                if value:
                    locations.append({'id': place['id'], 'query': place['query'], 'lat': place['lat'], 'lon': place['lon'], **value})
            elif not place.get('photoUrl'):
                with _lock:
                    # Bounded globally as well as per response, including queued futures.
                    if key not in _pending and len(_pending) < 24:
                        _pending.add(key)
                        _pool.submit(_fetch, dict(place), key)
                    awaiting = awaiting or key in _pending
    return dumps({'tripId': snapshot['id'], 'inputHash': fingerprint([{'id': p['id'], 'query': p['query'], 'lat': p['lat'], 'lon': p['lon']} for p in candidates]),
                  'locations': locations, 'pending': awaiting})
