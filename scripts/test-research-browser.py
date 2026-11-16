#!/usr/bin/env python3
"""Real Chromium regression for public research widgets; no network or trip writes.

Run with PYTHONPATH=workers:web workers/.venv/bin/python scripts/test-research-browser.py.
Uses a private temporary evidence directory and a tiny local form (not inventory).
"""
import os
import tempfile
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "workers"), str(ROOT / "web")]

from atlas_runtime.browser import ResearchBrowser
from server.planning_core import PlanningError


def main():
    with tempfile.TemporaryDirectory(prefix='detour-browser-test-') as directory:
        previous = os.environ.get('PLANNER_DATA_DIR')
        os.environ['PLANNER_DATA_DIR'] = directory
        browser = ResearchBrowser()
        try:
            browser.start()
            browser.page.set_content('''<!doctype html><title>Public search widget test</title>
                <span tabindex="0" onclick="document.querySelector('#calendar').hidden=false">Pick-up: Nov 18</span>
                <section id="calendar" hidden><button onclick="document.querySelector('#selected').textContent='Selected November 22'">22</button></section>
                <p id="selected"></p>''')
            initial = browser.capture()
            widget = next(control for control in initial['controls'] if control['tag'] == 'SPAN' and control['text'] == 'Pick-up: Nov 18')
            opened = browser.call('browser_click', {'ref': widget['ref']})
            day = next(control for control in opened['controls'] if control['tag'] == 'BUTTON' and control['text'] == '22')
            selected = browser.call('browser_click', {'ref': day['ref']})
            assert 'Selected November 22' in selected['text']
            try:
                browser.call('browser_click', {'ref': widget['ref']})
            except PlanningError as exc:
                assert 'expired' in str(exc)
            else:
                raise AssertionError('A prior capture ref must not retarget a current widget')
            assert len(list((Path(directory) / 'evidence').glob('source-*.json'))) == 3
            print('Passed: focusable span date-picker, real click/result, stale-ref rejection; no network or user-trip writes.')
        finally:
            browser.close()
            if previous is None: os.environ.pop('PLANNER_DATA_DIR', None)
            else: os.environ['PLANNER_DATA_DIR'] = previous


if __name__ == '__main__': main()
