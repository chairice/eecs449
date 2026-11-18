#!/usr/bin/env python3
"""Native local media integration; isolated test accounts only, no model calls.

Checks the actual registered HTTP endpoints, public photo provenance, ownership,
input binding and preservation of saved state. Source outages are reported as
unavailable imagery rather than mistaken for a live photo acceptance pass.
"""
from __future__ import annotations
import copy
import importlib.util
import json
import os
from pathlib import Path
import secrets
import time
from urllib.parse import urlsplit

_MODULE = Path(__file__).with_name('test-studio-api.py')
_spec = importlib.util.spec_from_file_location('detour_native_api_test', _MODULE)
_api = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_api)
rpc, account = _api.rpc, _api.account


def fixture():
    state = _api.fresh()
    state['snapshot'].update(title='Isolated media integration check', detail='LOGISTICS')
    state['snapshot']['places'] = [{'id': 'media-bridge', 'query': 'Golden Gate Bridge, San Francisco, CA',
        'label': 'Golden Gate Bridge', 'kind': 'PLACE', 'lat': 37.8199, 'lon': -122.4783,
        'timezone': 'America/Los_Angeles'}]
    state['snapshot']['days'] = [{'id': 'media-day', 'date': '2026-11-23', 'title': 'Photo source check',
        'items': [{'id': 'media-stop', 'title': 'Golden Gate Bridge', 'placeId': 'media-bridge', 'startTime': '10:00'}]}]
    return state


def verify_payload(value, state):
    assert not value.get('error'), 'Media endpoint returned an error'
    assert value.get('tripId') == state['snapshot']['id'], 'Media returned another trip identity'
    assert isinstance(value.get('pending'), bool), 'Missing bounded refresh state'
    assert isinstance(value.get('inputHash'), str) and value['inputHash'], 'Missing input binding'
    places = {p['id']: p for p in state['snapshot']['places']}
    for photo in value.get('locations', []):
        place = places.get(photo.get('id'))
        assert place is not None, 'Media included an unrelated place'
        for key in ['query', 'lat', 'lon']:
            assert photo.get(key) == place[key], 'Media source did not match current place inputs'
        image, source = urlsplit(photo.get('photoUrl', '')), urlsplit(photo.get('photoSourceUrl', ''))
        assert image.scheme == 'https' and image.hostname in {'upload.wikimedia.org', 'thumb.wikimedia.org'}, 'Unexpected image source'
        assert source.scheme == 'https' and source.hostname == 'commons.wikimedia.org', 'Missing public file provenance'
        assert photo.get('photoAttribution') and photo.get('photoLicense'), 'Missing public license or author'
    return value


def await_media(name, args, state, token='', seconds=25):
    deadline = time.monotonic() + seconds
    while True:
        value = verify_payload(rpc(name, args, token), state)
        if not value['pending'] or time.monotonic() >= deadline:
            return value
        time.sleep(1)


def main():
    checks = []
    assert rpc('planner_media', {'trip_id': 'no-such-trip'}).get('httpStatus') == 401
    checks.append('account media rejects unauthenticated access')
    first, other = account(), account()
    initial = fixture()
    proposed = copy.deepcopy(initial['snapshot']); proposed['title'] = 'Isolated media trip with Undo'
    proposal_id = 'media-proposal-' + secrets.token_hex(8)
    initial['pending'] = {'id': proposal_id, 'snapshot': proposed, 'warnings': []}
    saved = rpc('planner_import', {'state_json': json.dumps(initial), 'token': ''}, first)
    assert not saved.get('error'), 'Unable to create isolated test trip'
    saved = rpc('planner_approve', {'trip_id': saved['id'], 'proposal_id': proposal_id,
        'revision': 0, 'command_id': 'media-command-' + secrets.token_hex(8)}, first)
    assert saved.get('revision') == 1 and saved.get('undo'), 'Native test Undo was not established'
    before = rpc('planner_get', {'trip_id': saved['id']}, first)
    foreign = rpc('planner_media', {'trip_id': saved['id']}, other)
    assert foreign.get('error') and not foreign.get('locations'), 'Media leaked an unrelated account trip'
    checks.append('account media rejects another owner')
    native = await_media('planner_media', {'trip_id': saved['id']}, before, first)
    checks.append('registered account endpoint returns input-bound public media')
    after = rpc('planner_get', {'trip_id': saved['id']}, first)
    for key in ['snapshot', 'revision', 'undo', 'undoHistory', 'pending', 'conversation']:
        assert after.get(key) == before.get(key), 'Auxiliary media changed saved ' + key
    checks.append('account snapshot/revision/Undo/conversation remain unchanged')

    guest = fixture()
    guest.update(revision=7, undo={'revision': 7, 'label': 'Guest work kept'}, undoHistory=[{'snapshot': copy.deepcopy(guest['snapshot'])}])
    guest_before = copy.deepcopy(guest)
    args = {'state_json': json.dumps(guest)}
    public = await_media('planner_guest_media', args, guest)
    assert guest == guest_before and 'snapshot' not in public and 'revision' not in public and 'undo' not in public
    checks.append('registered guest endpoint keeps device itinerary and Undo untouched')
    checks.append('guest photo identity/coordinates/author/license provenance validated')
    changed = copy.deepcopy(guest)
    changed['snapshot']['places'][0]['query'] = 'Detour QA unmatched venue ' + secrets.token_hex(12)
    changed['snapshot']['places'][0]['label'] = 'Unmatched test venue'
    changed_response = verify_payload(rpc('planner_guest_media', {'state_json': json.dumps(changed)}), changed)
    assert changed_response['inputHash'] != public['inputHash'], 'Changed query reused the old input binding'
    assert changed_response['locations'] == [], 'Changed query copied a stale photograph'
    checks.append('same place ID with changed query never reuses an old photo')
    moved = copy.deepcopy(guest)
    moved['snapshot']['places'][0].update(lat=30.0, lon=-100.0)
    moved_response = verify_payload(rpc('planner_guest_media', {'state_json': json.dumps(moved)}), moved)
    assert moved_response['inputHash'] != public['inputHash'] and moved_response['locations'] == []
    checks.append('changed coordinates never reuse old imagery')
    invalid = rpc('planner_guest_media', {'state_json': '{}'})
    assert invalid.get('error') and 'locations' not in invalid
    checks.append('malformed guest state fails without exposing saved trip data')
    photos = public.get('locations', []) or native.get('locations', [])
    result = {'passed': len(checks), 'checks': checks,
        'livePhoto': 'available' if photos else 'unavailable',
        'photoLicenses': sorted({p['photoLicense'] for p in photos}),
        'snapshotUnchanged': True, 'undoUnchanged': True}
    output = Path(os.environ.get('DETOUR_MEDIA_TEST_RESULT', '/tmp/detour-media-native-check.json'))
    output.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS:', len(checks), 'native media checks; live Golden Gate Bridge photo', result['livePhoto'],
          '; ownership, provenance, input binding, snapshot and Undo preserved')


if __name__ == '__main__':
    main()
