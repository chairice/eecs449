"""Bounded, cached Wikimedia photos matched to an already located place."""
from __future__ import annotations
import html
import json
import math
import re
import time
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen
from server.planning_jobs import connection


def _get(endpoint, params):
    req = Request(endpoint + '?' + urlencode({'action': 'query', 'format': 'json', 'formatversion': 2, **params}),
                  headers={'User-Agent': 'DetourTripPlanner/0.1 (place photographs; https://github.com/bhavye/eecs449-team)'})
    with urlopen(req, timeout=2.5) as response:
        return json.loads(response.read(1_000_000))


def _plain(value):
    return html.unescape(re.sub('<[^>]+>', '', str(value))).strip()[:1000]


def _name(value):
    return ' '.join(re.findall('[a-z0-9]+', value.casefold())).removeprefix('the ')


def lookup(place):
    target = place['query'].split(',')[0].strip()
    data = _get('https://en.wikipedia.org/w/api.php', {'generator': 'search', 'gsrsearch': 'intitle:"' + target + '"',
        'gsrnamespace': 0, 'gsrlimit': 4, 'prop': 'pageimages|coordinates', 'piprop': 'thumbnail|name',
        'pithumbsize': 1000, 'pilicense': 'free', 'colimit': 1})
    eligible = []
    for page in data.get('query', {}).get('pages', []):
        # Exact entity title plus nearby coordinates prevents a similarly named venue photo.
        if _name(page.get('title', '').split(',')[0]) != _name(target): continue
        coords = page.get('coordinates', [])
        if not coords or not page.get('pageimage') or not page.get('thumbnail', {}).get('source'): continue
        c = coords[0]
        distance = math.hypot((c['lat'] - place['lat']) * 111,
                              (c['lon'] - place['lon']) * 111 * math.cos(math.radians(place['lat'])))
        if distance <= 25: eligible.append(page)
    if len(eligible) != 1: return None
    page = eligible[0]
    url = page['thumbnail']['source']
    if urlsplit(url).scheme != 'https' or urlsplit(url).hostname not in {'upload.wikimedia.org', 'thumb.wikimedia.org'}: return None
    meta = _get('https://commons.wikimedia.org/w/api.php', {'titles': 'File:' + page['pageimage'],
        'prop': 'imageinfo', 'iiprop': 'url|extmetadata'})
    info = next((p.get('imageinfo', [{}])[0] for p in meta.get('query', {}).get('pages', []) if p.get('imageinfo')), {})
    extra = info.get('extmetadata', {})
    license_name = _plain(extra.get('LicenseShortName', {}).get('value', ''))
    artist = _plain(extra.get('Artist', {}).get('value', ''))
    source = info.get('descriptionurl', '')
    if not license_name or not artist or not source.startswith('https://commons.wikimedia.org/'): return None
    if not re.search(r'\b(CC|public domain|PD|CC0)\b', license_name, re.I): return None
    return {'photoUrl': url, 'photoSourceUrl': source, 'photoAttribution': artist,
            'photoLicense': license_name, 'photoTitle': page['title']}


def resolve_photo(place):
    if place.get('lat') is None or place.get('lon') is None or place.get('kind') == 'AIRPORT': return None
    key = 'v1:' + place['query'].casefold() + ':' + str(round(place['lat'], 3)) + ':' + str(round(place['lon'], 3))
    with connection() as db:
        db.execute('CREATE TABLE IF NOT EXISTS place_photos (query TEXT PRIMARY KEY, value TEXT, updated REAL)')
        row = db.execute('SELECT * FROM place_photos WHERE query=?', (key,)).fetchone()
        if row and row['updated'] > time.time() - (86400 * 30 if row['value'] != 'null' else 86400):
            return json.loads(row['value'])
    try: result = lookup(place)
    except Exception: result = None  # Imagery never makes an otherwise usable trip fail.
    with connection() as db:
        db.execute('INSERT OR REPLACE INTO place_photos VALUES(?,?,?)', (key, json.dumps(result), time.time()))
    return result
