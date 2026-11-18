"""Observed flight segments with catalog airport identities and time-zone arithmetic."""
from __future__ import annotations
import copy
import re
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from server.planning_core import PlanningError, calendar, clock, integer, text


def airport(code):
    from .geography import catalog, zone_finder
    code = text(code, 'airport code', 3, empty=False).upper()
    if not re.fullmatch('[A-Z]{3}', code):
        raise PlanningError('Use the observed IATA airport code for each flight segment.')
    found = [p for p in catalog() if p.get('kind') == 'AIRPORT' and p.get('code') == code]
    if len(found) != 1:
        raise PlanningError('The flight segment airport is not in the airport catalog.')
    p = found[0]
    try: zone = zone_finder().timezone_at(lat=p['lat'], lng=p['lon']) or ''
    except Exception: zone = ''
    return {'code': code, 'label': p['name'], 'lat': p['lat'], 'lon': p['lon'], 'timezone': zone,
            'sourceUrl': 'https://ourairports.com/'}


def instant(day, at, airport_value):
    if not day or not at or not airport_value.get('timezone'): return None
    try: return datetime.fromisoformat(day + 'T' + at).replace(tzinfo=ZoneInfo(airport_value['timezone'])).astimezone(timezone.utc)
    except (ValueError, ZoneInfoNotFoundError): return None


def normalized_segments(raw, flight, query, corpus, source_url):
    """Require individual observed airport/time excerpts; never infer a connection."""
    from .browser import _observed, _fact_matches
    if not isinstance(raw, list) or not 1 <= len(raw) <= 7:
        raise PlanningError('A flight journey needs one to seven observed segments.')
    result = []
    for value in raw:
        if not isinstance(value, dict): raise PlanningError('Invalid flight segment.')
        excerpt = text(value.get('excerpt', ''), 'segment evidence', 5000, empty=False)
        if not _observed(excerpt, corpus): raise PlanningError('The flight segment was not observed.')
        start, end = airport(value.get('fromCode')), airport(value.get('toCode'))
        for code in [start['code'], end['code']]:
            if not re.search(r'(?<![A-Za-z])' + re.escape(code) + r'(?![A-Za-z])', excerpt):
                raise PlanningError('Each connection airport needs its observed airport code.')
        part = {'fromCode': start['code'], 'toCode': end['code'], 'fromAirport': start, 'toAirport': end,
                'airline': text(value.get('airline', ''), 'segment airline', 200),
                'flightNumber': text(value.get('flightNumber', ''), 'flight number', 40), 'sourceUrl': source_url}
        if start['code'] == end['code']: raise PlanningError('A flight segment needs different airports.')
        for key in ['departDate', 'arriveDate']:
            part[key] = calendar(value.get(key, ''), key)
            if part[key] and part[key] != query.get('departDate'):
                date_excerpt = value.get('dateExcerpt', excerpt)
                if not _observed(date_excerpt, corpus) or not _fact_matches(part[key], date_excerpt, key):
                    raise PlanningError('A next-day flight date needs observed date evidence.')
        for key in ['departTime', 'arriveTime']:
            part[key] = clock(value.get(key, ''), key)
            time_excerpt = re.sub(r'(?<=\d)\s*([AP]M)(?=[A-Z])', r' \1 ', excerpt)
            if part[key] and not _fact_matches(part[key], time_excerpt, 'pickupTime'):
                raise PlanningError('Segment local times need matching observed schedule text.')
        for key in ['airline', 'flightNumber']:
            observed_value = ' '.join(excerpt.split()).casefold()
            proposed_value = ' '.join(part[key].split()).casefold()
            if key == 'flightNumber':
                observed_value, proposed_value = re.sub(r'\s+', '', observed_value), re.sub(r'\s+', '', proposed_value)
            if part[key] and proposed_value not in observed_value:
                raise PlanningError('Segment carrier and flight number need matching observed text.')
        departure, arrival = instant(part['departDate'], part['departTime'], start), instant(part['arriveDate'], part['arriveTime'], end)
        supplied = integer(value.get('durationMinutes'), 'segment duration', 1, 3000, nullable=True)
        if departure and arrival:
            duration = int((arrival - departure).total_seconds() // 60)
            if not 1 <= duration <= 3000: raise PlanningError('A flight segment arrival must follow departure in its local time zone.')
            if supplied is not None and abs(duration - supplied) > 1: raise PlanningError('Segment duration disagrees with its local dates and times.')
            part['durationMinutes'] = duration
        else:
            # A number without an observed duration excerpt cannot become evidence.
            part['durationMinutes'] = None
        part['layoverMinutes'] = None
        result.append(part)
    if result[0]['fromCode'] != query.get('origin') or result[-1]['toCode'] != query.get('destination'):
        raise PlanningError('The flight segments do not match the searched route.')
    if query.get('departDate') and result[0]['departDate'] != query['departDate']:
        raise PlanningError('The first flight segment has the wrong departure date.')
    if flight.get('stops') is not None and flight['stops'] != len(result) - 1:
        raise PlanningError('The segment count disagrees with the observed stop count.')
    for side, segment in [('depart', result[0]), ('arrive', result[-1])]:
        for suffix in ['Date', 'Time']:
            key = side + suffix
            if flight.get(key) and flight[key] != segment.get(key):
                raise PlanningError('The segment schedule differs from the selected flight.')
    for previous, following in zip(result, result[1:]):
        if previous['toCode'] != following['fromCode']:
            raise PlanningError('The flight segments do not share a connecting airport.')
        first = instant(previous['arriveDate'], previous['arriveTime'], previous['toAirport'])
        second = instant(following['departDate'], following['departTime'], following['fromAirport'])
        if first and second:
            minutes = int((second - first).total_seconds() // 60)
            if not 0 <= minutes <= 4320: raise PlanningError('Flight connections must follow arrival.')
            previous['layoverMinutes'] = minutes
    if all(s['durationMinutes'] is not None for s in result) and all(s['layoverMinutes'] is not None for s in result[:-1]):
        total = sum(s['durationMinutes'] for s in result) + sum(s['layoverMinutes'] for s in result[:-1])
        if flight.get('durationMinutes') is not None and abs(total - flight['durationMinutes']) > 1:
            raise PlanningError('The detailed journey duration differs from the selected flight.')
    return result


def complete_flight(flight, segments):
    """Hydrate missing aggregate facts solely from normalized observed segments."""
    value = copy.deepcopy(flight)
    value['segments'] = segments
    for side, segment in [('depart', segments[0]), ('arrive', segments[-1])]:
        for suffix in ['Date', 'Time']:
            key = side + suffix
            if value.get(key) in (None, ''):
                value[key] = segment.get(key, '')
    if value.get('stops') is None: value['stops'] = len(segments) - 1
    if not value.get('airline'):
        value['airline'] = ' / '.join(dict.fromkeys(s['airline'] for s in segments if s.get('airline')))
    if value.get('durationMinutes') is None and all(p['durationMinutes'] is not None for p in segments) and all(p['layoverMinutes'] is not None for p in segments[:-1]):
        value['durationMinutes'] = sum(p['durationMinutes'] for p in segments) + sum(p['layoverMinutes'] for p in segments[:-1])
    return value


def check_selected_schedule(flight, leg):
    for key in ['departDate', 'arriveDate', 'departTime', 'arriveTime', 'durationMinutes']:
        if leg.get(key) not in (None, '') and flight.get(key) not in (None, '') and leg[key] != flight[key]:
            raise PlanningError('The observed segment schedule differs from the current selected leg.')


def refreshed_journey(original, raw, source, selected_leg=None):
    """Enrich an owned quote without modifying its fare or observed schedule."""
    corpus = source['text'] + '\n' + source.get('structure', '')
    flight = copy.deepcopy(original.get('flight', {}))
    segments = normalized_segments(raw, flight, original['query'], corpus, source['url'])
    flight = complete_flight(flight, segments)
    if selected_leg is not None: check_selected_schedule(flight, selected_leg)
    flight.update(journeyObservedAt=source['observedAt'], journeySourceUrl=source['url'])
    value = copy.deepcopy(original)
    value['flight'] = flight
    return value


def journey_for_leg(snapshot, leg_id, raw, source):
    """Sourced schedule for an existing manual/imported leg; contains no fare."""
    from server.planning_api import _airport_code
    from server.planning_core import journey_signature
    leg = next((part for part in snapshot['legs'] if part['id'] == leg_id and part['mode'] == 'FLIGHT'), None)
    if not leg: raise PlanningError('This flight is not in the current trip.')
    places = {p['id']: p for p in snapshot['places']}
    query = {'origin': _airport_code(places[leg['fromId']]), 'destination': _airport_code(places[leg['toId']]), 'departDate': leg['departDate']}
    if not query['origin'] or not query['destination']:
        raise PlanningError('The saved flight needs identified origin and destination airports first.')
    flight = {key: leg.get(key) for key in ['departDate', 'departTime', 'arriveDate', 'arriveTime', 'durationMinutes']}
    segments = normalized_segments(raw, flight, query, source['text'] + '\n' + source.get('structure', ''), source['url'])
    flight = complete_flight(flight, segments)
    check_selected_schedule(flight, leg)
    flight['stops'] = len(segments) - 1
    flight['airline'] = ' / '.join(dict.fromkeys(s['airline'] for s in segments if s.get('airline')))
    if not flight.get('durationMinutes') and all(p['durationMinutes'] is not None for p in segments) and all(p['layoverMinutes'] is not None for p in segments[:-1]):
        flight['durationMinutes'] = sum(p['durationMinutes'] for p in segments) + sum(p['layoverMinutes'] for p in segments[:-1])
    return {'id': 'journey-' + leg_id, 'legId': leg_id, 'legSignature': journey_signature(snapshot, leg), 'flight': flight, 'captureId': source['captureId'], 'sourceUrl': source['url'], 'observedAt': source['observedAt']}
