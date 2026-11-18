#!/usr/bin/env python3
"""Opt-in actual-model QA using ONLY a newly constructed public flight fixture.

Does not read any application ledger, saved trip, earlier request, conversation,
profile, preference, attachment, or source capture. Only the public airline/route/
date/schedule below plus catalog airport geography are sent to the model/browser.
"""
from __future__ import annotations
import argparse
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-live', action='store_true')
    parser.add_argument('--seconds', type=int, default=180)
    parser.add_argument('--max-clicks', type=int, default=6)
    args = parser.parse_args()
    if not args.run_live: parser.error('This sends the public QA fixture to the configured model; pass --run-live explicitly.')
    root = Path(__file__).resolve().parents[1]
    directory = Path(tempfile.mkdtemp(prefix='detour-public-flight-qa-'))
    os.environ['PLANNER_DATA_DIR'] = str(directory)
    os.environ['PLANNER_CAPTURE_REJECTIONS'] = '1'
    os.environ['DETOUR_EMBEDDED_WORKER'] = 'off'
    sys.path[:0] = [str(root / 'web')]
    from dotenv import load_dotenv
    load_dotenv(root / 'workers/.env')
    from server import planning_jobs as jobs, planning_api as api
    from server.planning_core import dumps, validate_trip
    from atlas_runtime.flight_journey import airport
    from atlas_runtime import planner
    state = api.fresh()
    snapshot = state['snapshot']
    snapshot.update(title='Public flight research QA', startDate='2026-11-25', endDate='2026-11-25', detail='LOGISTICS')
    snapshot['places'] = [{'id': code.lower(), 'query': code, 'label': code, 'kind': 'AIRPORT',
        **{key: value for key, value in airport(code).items() if key in {'lat', 'lon', 'timezone'}}} for code in ['SFO', 'XNA']]
    snapshot['legs'] = [{'id': 'qa-flight', 'fromId': 'sfo', 'toId': 'xna', 'mode': 'FLIGHT',
        'departDate': '2026-11-25', 'arriveDate': '2026-11-25', 'departTime': '07:00', 'arriveTime': '15:28',
        'durationMinutes': 388, 'notes': 'American, one stop. Public schedule QA fixture, no fare or booking.', 'locked': True}]
    state['snapshot'] = validate_trip(snapshot)
    before = copy.deepcopy(state)
    request = {'tripId': state['id'], 'snapshot': state['snapshot'], 'baseRevision': 0,
        'message': 'Research and save the connection airport, flight numbers, individual flight times and durations, and layover for this exact existing American SFO to XNA flight on November 25, 2026, 07:00 to 15:28, total 388 minutes. Preserve the exact saved flight. Do not search alternative fares or make any itinerary edit. Use the observed public schedule to attach read-only journey details.',
        'clientTurnId': 'public-flight-details-qa', 'today': '2026-11-16', 'timeZone': 'America/Detroit',
        'contextRefs': [{'id': 'qa-flight', 'scope': 'APPROVED'}], 'conversation': [], 'attachments': [],
        'workingContext': {}, 'preferences': {}, 'summary': '', 'researchContext': {'offers': []}}
    owner = 'account:public-flight-qa'
    job_id = jobs.enqueue(owner, dumps(request))
    queued = api.record_job(dumps(state), dumps(request), job_id)
    leased = jobs.claim('public-flight-qa')
    started, last, clicks = time.monotonic(), [''], [0]
    base_browser = planner.ResearchBrowser
    class TracedBrowser(base_browser):
        def call(self, name, data):
            if name == 'browser_click':
                clicks[0] += 1
                print('CLICK', clicks[0], data.get('ref'), flush=True)
                try:
                    element = self.element(data.get('ref'))
                    print('TARGET', element.get_attribute('aria-label') or (element.inner_text() or '')[:180], flush=True)
                except Exception as error: print('TARGET_ERROR', type(error).__name__, flush=True)
            value = super().call(name, data)
            if name == 'browser_click':
                print('CLICK_OUTCOME', any(c.get('expanded') == 'true' for c in value.get('controls', [])), flush=True)
            return value
    planner.ResearchBrowser = TracedBrowser
    def update(message):
        if message != last[0]: print(message, flush=True); last[0] = message
        return jobs.progress(job_id, leased['lease_token'], message)
    print('PUBLIC_ONLY_QA', str(directory), flush=True)
    try:
        result = planner.plan(request, owner, update=update,
            running=lambda: time.monotonic() - started < args.seconds and clicks[0] <= args.max_clicks)
        jobs.finish(job_id, leased['lease_token'], result)
        final = api.stage(queued, owner, job_id)
        journeys = [j for j in final.get('flightJourneys', []) if j['legId'] == 'qa-flight']
        checks = {'no_plan_operations': result['operations'] == [], 'snapshot_unchanged': final['snapshot'] == before['snapshot'],
            'revision_unchanged': final['revision'] == before['revision'], 'undo_unchanged': final.get('undo') == before.get('undo'),
            'no_fare_invented': final.get('offers') == before.get('offers'), 'actual_sources': result.get('sourceCount', 0) > 0,
            'two_sourced_segments': len(journeys) == 1 and len(journeys[0]['flight']['segments']) == 2}
        output = {'checks': checks, 'jobId': job_id, 'sourceCount': result.get('sourceCount'), 'journeys': journeys, 'elapsed': round(time.monotonic() - started, 2)}
        (directory / 'result.json').write_text(json.dumps(output, indent=2))
        print('CHECKS', json.dumps(checks), flush=True)
        if not all(checks.values()): raise AssertionError('Public flight QA failed acceptance checks.')
    except BaseException as exc:
        jobs.cancel(owner, job_id)
        print('FAILED', type(exc).__name__, flush=True)
        raise
    finally: planner.ResearchBrowser = base_browser


if __name__ == '__main__': main()
