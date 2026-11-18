"""Trip-resource regressions. Schedules in these tests are synthetic fixtures."""
import copy
import json
import time
import pytest
from atlas_runtime.flight_journey import normalized_segments, refreshed_journey
from atlas_runtime.planner import checked_activity_actions
from server.planning_core import PlanningError, blank_trip, dumps, validate_trip
from server import planning_media, place_photos
from server.planning_jobs import connection


def journey():
    query = {'origin': 'SFO', 'destination': 'XNA', 'departDate': '2026-11-25'}
    flight = {'airline': 'American', 'departDate': '2026-11-25', 'arriveDate': '2026-11-25',
              'departTime': '07:00', 'arriveTime': '15:28', 'durationMinutes': 388, 'stops': 1}
    raw = [dict(fromCode='SFO', toCode='DFW', airline='American', flightNumber='AA111', departDate='2026-11-25', arriveDate='2026-11-25', departTime='07:00', arriveTime='12:30', excerpt='American AA111 SFO 7:00 am DFW 12:30 pm'),
           dict(fromCode='DFW', toCode='XNA', airline='American', flightNumber='AA222', departDate='2026-11-25', arriveDate='2026-11-25', departTime='14:20', arriveTime='15:28', excerpt='American AA222 DFW 2:20 pm XNA 3:28 pm')]
    corpus = '\n'.join(p['excerpt'] for p in raw)
    return query, flight, raw, corpus


def test_observed_connection_uses_catalog_airports_and_timezone_durations():
    query, flight, raw, corpus = journey()
    before = copy.deepcopy(raw)
    segments = normalized_segments(raw, flight, query, corpus, 'https://www.aa.com/')
    assert [(s['fromCode'], s['toCode']) for s in segments] == [('SFO', 'DFW'), ('DFW', 'XNA')]
    assert [s['durationMinutes'] for s in segments] == [210, 68]
    assert [s['layoverMinutes'] for s in segments] == [110, None]
    assert segments[0]['toAirport']['timezone'] == 'America/Chicago'
    assert segments[0]['toAirport']['lat'] is not None
    assert raw == before


@pytest.mark.parametrize('field,value', [('departTime', '08:00'), ('arriveTime', '16:28'), ('arriveDate', '2026-11-26'), ('durationMinutes', 400), ('stops', 2)])
def test_segments_reject_a_schedule_that_differs_from_the_selected_quote(field, value):
    query, flight, raw, corpus = journey()
    flight[field] = value
    with pytest.raises(PlanningError): normalized_segments(raw, flight, query, corpus, 'https://www.aa.com/')


def test_segment_cannot_invent_an_airport_or_unobserved_next_day_rollover():
    query, flight, raw, corpus = journey()
    raw[0]['toCode'] = 'DEN'
    with pytest.raises(PlanningError, match='observed airport code'): normalized_segments(raw, flight, query, corpus, 'https://www.aa.com/')
    query, flight, raw, corpus = journey()
    raw[1]['arriveDate'] = '2026-11-26'
    with pytest.raises(PlanningError, match='date evidence'): normalized_segments(raw, flight, query, corpus, 'https://www.aa.com/')


def test_refreshed_historical_journey_preserves_quote_id_price_and_original_timestamp():
    query, flight, raw, corpus = journey()
    original = {'id': 'existing', 'query': query, 'flight': flight, 'observedAt': 10, 'price': {'amountMinor': 54321, 'currency': 'USD'}}
    old = copy.deepcopy(original)
    updated = refreshed_journey(original, raw, {'text': corpus, 'url': 'https://www.aa.com/schedule', 'observedAt': 20})
    assert original == old
    assert updated['id'] == old['id'] and updated['price'] == old['price'] and updated['observedAt'] == old['observedAt']
    assert updated['flight']['journeyObservedAt'] == 20
    assert len(updated['flight']['segments']) == 2


def test_activity_links_must_be_captured_or_user_supplied_and_old_links_remain():
    snapshot = blank_trip('trip')
    request = {'snapshot': snapshot, 'message': 'Use https://example.com/booking', 'conversation': []}
    operations = [{'action': 'upsert_item', 'value': {'actions': [{'label': 'Ferry schedule', 'url': 'https://ferry.example/schedule'}]}}]
    with pytest.raises(PlanningError, match='actual captured'): checked_activity_actions(operations, request, {})
    checked_activity_actions(operations, request, {'capture': {'url': 'https://ferry.example/', 'controls': [{'href': 'https://ferry.example/schedule'}]}})
    operations[0]['value']['actions'][0]['url'] = 'https://example.com/booking'
    checked_activity_actions(operations, request, {})


def media_trip():
    s = blank_trip('media-trip')
    s['places'] = [{'id': 'bridge', 'query': 'Golden Gate Bridge, San Francisco, CA', 'label': 'Golden Gate Bridge', 'kind': 'PLACE', 'lat': 37.8199, 'lon': -122.4783}]
    return validate_trip(s)


def test_cached_photo_auxiliary_read_never_changes_snapshot_revision_or_undo(tmp_path, monkeypatch):
    monkeypatch.setenv('PLANNER_DATA_DIR', str(tmp_path))
    snapshot = media_trip()
    state = {'snapshot': snapshot, 'revision': 8, 'undo': {'snapshot': {'title': 'before'}}}
    before = dumps(state)
    photo = {'photoUrl': 'https://upload.wikimedia.org/test.jpg', 'photoSourceUrl': 'https://commons.wikimedia.org/wiki/File:Test.jpg', 'photoAttribution': 'Fixture author', 'photoLicense': 'CC BY 4.0'}
    with connection() as db:
        db.execute('CREATE TABLE place_photos (query TEXT PRIMARY KEY, value TEXT, updated REAL)')
        db.execute('INSERT INTO place_photos VALUES(?,?,?)', (planning_media._key(snapshot['places'][0]), json.dumps(photo), time.time()))
    result = json.loads(planning_media.media_json(before))
    assert result['tripId'] == snapshot['id'] and result['locations'][0]['id'] == 'bridge'
    assert result['locations'][0]['photoAttribution'] == 'Fixture author'
    assert result['pending'] is False and dumps(state) == before


def test_photo_lookup_matches_entity_coordinates_and_preserves_license(monkeypatch):
    calls = []
    def get(endpoint, params):
        calls.append(endpoint)
        if 'en.wikipedia' in endpoint:
            return {'query': {'pages': [{'title': 'Golden Gate Bridge', 'pageimage': 'Bridge.jpg', 'thumbnail': {'source': 'https://thumb.wikimedia.org/Bridge.jpg'}, 'coordinates': [{'lat': 37.8199, 'lon': -122.4783}]}]}}
        return {'query': {'pages': [{'imageinfo': [{'descriptionurl': 'https://commons.wikimedia.org/wiki/File:Bridge.jpg', 'extmetadata': {'Artist': {'value': '<a>Photographer</a>'}, 'LicenseShortName': {'value': 'CC BY-SA 4.0'}}}]}]}}
    monkeypatch.setattr(place_photos, '_get', get)
    p = media_trip()['places'][0]
    value = place_photos.lookup(p)
    assert value['photoAttribution'] == 'Photographer' and value['photoLicense'] == 'CC BY-SA 4.0'
    assert len(calls) == 2
    p['lat'] = 30
    assert place_photos.lookup(p) is None


def test_photo_outage_is_negative_cached_and_does_not_break_plan(tmp_path, monkeypatch):
    monkeypatch.setenv('PLANNER_DATA_DIR', str(tmp_path))
    calls = []
    def failed(_): calls.append(1); raise TimeoutError()
    monkeypatch.setattr(place_photos, 'lookup', failed)
    assert place_photos.resolve_photo(media_trip()['places'][0]) is None
    assert place_photos.resolve_photo(media_trip()['places'][0]) is None
    assert len(calls) == 1


def selected_trip():
    from atlas_runtime.flight_journey import airport
    s = blank_trip('selected-trip')
    s['places'] = [{'id': code.lower(), 'query': code, 'label': code, 'kind': 'AIRPORT', **{k: v for k, v in airport(code).items() if k in {'lat', 'lon', 'timezone'}}} for code in ['SFO', 'XNA']]
    s['legs'] = [{'id': 'selected-leg', 'fromId': 'sfo', 'toId': 'xna', 'mode': 'FLIGHT', 'departDate': '2026-11-25', 'arriveDate': '2026-11-25', 'departTime': '07:00', 'arriveTime': '15:28', 'durationMinutes': 388, 'offerId': 'original-offer', 'locked': True}]
    s['days'] = [{'id': 'other-day', 'date': '2026-11-23', 'title': 'Keep the offsite', 'items': [{'id': 'meeting', 'title': 'Team meeting', 'locked': True}]}]
    return validate_trip(s)


def test_model_tool_and_stage_complete_selected_flight_without_changing_plan_or_price(tmp_path, monkeypatch):
    from types import SimpleNamespace
    from atlas_runtime.planner import plan
    from server import planning_api as api, planning_jobs as jobs
    monkeypatch.setenv('PLANNER_DATA_DIR', str(tmp_path))
    query, flight, raw, corpus = journey()
    query.update(category='FLIGHT', adults=1, childrenAges=[])
    quote = {'id': 'original-offer', 'category': 'FLIGHT', 'query': query, 'flight': flight, 'observedAt': 10,
             'price': {'amountMinor': 54321, 'currency': 'USD', 'basis': 'PER_PERSON', 'from': False, 'quantity': 1, 'estimatedTotalMinor': 54321, 'feesIncluded': None}}
    snapshot = selected_trip()
    before = copy.deepcopy(snapshot)
    state = api.fresh(dumps({'snapshot': snapshot}))
    state.update(offers=[quote], revision=4, undo={'revision': 4, 'label': 'Previous user edit'})
    old_undo = copy.deepcopy(state['undo'])
    request = {'tripId': snapshot['id'], 'snapshot': snapshot, 'baseRevision': 4, 'message': 'Check my selected connection', 'clientTurnId': 'complete-journey', 'attachments': [], 'conversation': [], 'researchContext': {'offers': [quote]}}
    source = {'captureId': 'real_capture_fixture', 'url': 'https://www.aa.com/schedule', 'title': 'Flight schedule', 'observedAt': 20, 'text': corpus, 'structure': '', 'controls': []}
    class Browser:
        captures = {'real_capture_fixture': source}
        def close(self): pass
    class Block:
        type = 'tool_use'; id = 'fixture_tool'
        def __init__(self, name, value): self.name, self.input = name, value
        def model_dump(self, **_): return {'type': self.type, 'id': self.id, 'name': self.name, 'input': self.input}
    class Client:
        def __init__(self):
            self.messages = self
            self.responses = iter([Block('update_flight_journey', {'offerId': quote['id'], 'captureId': source['captureId'], 'segments': raw}),
                Block('finish_plan', {'assistantMessage': 'Your connection details are available.', 'operations': [], 'workingContext': {}, 'nextDecision': {}, 'summary': 'Same trip'})])
        def create(self, **_): return SimpleNamespace(content=[next(self.responses)], usage=SimpleNamespace(input_tokens=1, output_tokens=1))
    monkeypatch.setattr('atlas_runtime.planner.ResearchBrowser', Browser)
    monkeypatch.setattr('atlas_runtime.planner.trusted_history', lambda *_: [copy.deepcopy(quote)])
    result = plan(request, 'account:owner', client=Client())
    assert result['operations'] == [] and result['proposed'] == before
    assert result['offers'][0]['id'] == quote['id'] and result['offers'][0]['price'] == quote['price']
    assert len(result['offers'][0]['flight']['segments']) == 2
    job_id = jobs.enqueue('account:owner', dumps(request))
    state = json.loads(api.record_job(dumps(state), dumps(request), job_id))
    leased = jobs.claim('worker')
    jobs.finish(job_id, leased['lease_token'], result)
    updated = api.stage(dumps(state), 'account:owner', job_id)
    assert updated['snapshot'] == before and updated['revision'] == 4 and updated['undo'] == old_undo
    assert updated['offers'][0]['id'] == quote['id'] and updated['offers'][0]['price'] == quote['price']
    assert len(updated['offers'][0]['flight']['segments']) == 2


def test_unpriced_manual_flight_journey_is_bound_to_exact_leg_and_airport_identity():
    from atlas_runtime.flight_journey import journey_for_leg
    from server.planning_core import journey_signature
    query, flight, raw, corpus = journey()
    snapshot = selected_trip(); snapshot['legs'][0]['offerId'] = ''
    result = journey_for_leg(snapshot, 'selected-leg', raw, {'captureId': 'source', 'text': corpus, 'url': 'https://www.aa.com/', 'observedAt': 20})
    assert result['legSignature'] == journey_signature(snapshot, snapshot['legs'][0])
    assert len(result['flight']['segments']) == 2 and 'price' not in result
    old_signature = copy.deepcopy(result['legSignature'])
    snapshot['places'][1]['query'] = 'DEN'
    assert journey_signature(snapshot, snapshot['legs'][0]) != old_signature
    snapshot = selected_trip(); snapshot['legs'][0]['departTime'] = '08:00'
    with pytest.raises(PlanningError, match='schedule differs'):
        journey_for_leg(snapshot, 'selected-leg', raw, {'captureId': 'source', 'text': corpus, 'url': 'https://www.aa.com/', 'observedAt': 20})


def test_segment_clock_parser_accepts_real_page_concatenated_labels_without_changing_evidence():
    query, flight, raw, corpus = journey()
    raw[1]['excerpt'] = 'American AA 222 DFW 2:20 PMDallas XNA 3:28 PMNorthwest'
    corpus = raw[0]['excerpt'] + '\n' + raw[1]['excerpt']
    assert normalized_segments(raw, flight, query, corpus, 'https://www.aa.com/')[1]['durationMinutes'] == 68


@pytest.mark.parametrize('field,value', [('departTime', '08:00'), ('arriveTime', '16:28'), ('durationMinutes', 400)])
def test_new_or_changed_selected_flight_cannot_reuse_a_conflicting_schedule(field, value):
    from server.planning_api import validate_selections
    query, flight, raw, corpus = journey()
    query.update(category='FLIGHT', adults=1, childrenAges=[])
    snapshot = selected_trip()
    quote = {'id': 'original-offer', 'category': 'FLIGHT', 'query': query, 'flight': flight}
    before = copy.deepcopy(snapshot)
    snapshot['legs'][0][field] = value
    with pytest.raises(PlanningError, match='schedule differs'):
        validate_selections(snapshot, {quote['id']: quote}, before)


def test_legacy_incomplete_selected_flight_remains_usable_without_invented_fields():
    from server.planning_api import validate_selections
    query, flight, raw, corpus = journey()
    query.update(category='FLIGHT', adults=1, childrenAges=[])
    snapshot = selected_trip()
    snapshot['legs'][0].update(departTime='', arriveTime='', durationMinutes=None)
    quote = {'id': 'original-offer', 'category': 'FLIGHT', 'query': query, 'flight': flight}
    validate_selections(snapshot, {quote['id']: quote})
    # A read/other edit does not brick an old internally inconsistent record.
    snapshot['legs'][0].update(departTime='08:00')
    validate_selections(snapshot, {quote['id']: quote}, copy.deepcopy(snapshot))


def test_imported_plain_text_or_pdf_links_remain_user_material():
    request = {'snapshot': blank_trip('imported'), 'message': 'Import my offsite', 'conversation': []}
    op = [{'action': 'upsert_item', 'value': {'actions': [{'label': 'Booking', 'url': 'https://venue.example/my-booking'}]}}]
    checked_activity_actions(op, request, {}, 'User PDF itinerary:\nhttps://venue.example/my-booking')


def test_missing_aggregate_endpoints_are_hydrated_from_observed_segments_and_checked_against_current_leg():
    query, flight, raw, corpus = journey()
    original = {'id': 'old-incomplete', 'query': query, 'flight': {'stops': 1}, 'price': {'amountMinor': 12345, 'currency': 'USD'}, 'observedAt': 10}
    source = {'text': corpus, 'url': 'https://www.aa.com/', 'observedAt': 20}
    selected = selected_trip()['legs'][0]
    updated = refreshed_journey(original, raw, source, selected)
    for key in ['departDate', 'arriveDate', 'departTime', 'arriveTime', 'durationMinutes']:
        assert updated['flight'][key] == flight[key]
    assert updated['price'] == original['price'] and updated['observedAt'] == 10
    selected['departTime'] = '08:00'
    with pytest.raises(PlanningError, match='current selected leg'):
        refreshed_journey(original, raw, source, selected)


def test_new_segmented_offer_aggregate_contract_is_complete_even_if_provider_outer_fields_missing():
    from atlas_runtime.flight_journey import complete_flight
    query, flight, raw, corpus = journey()
    segments = normalized_segments(raw, {}, query, corpus, 'https://www.aa.com/')
    completed = complete_flight({}, segments)
    assert completed['departTime'] == '07:00' and completed['arriveTime'] == '15:28'
    assert completed['departDate'] == completed['arriveDate'] == '2026-11-25'
    assert completed['durationMinutes'] == 388 and completed['stops'] == 1
