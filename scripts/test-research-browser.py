#!/usr/bin/env python3
"""Real Chromium regression for public research widgets; no network or trip writes.

Run with workers/.venv/bin/python scripts/test-research-browser.py.
Uses a private temporary evidence directory and a tiny local form (not inventory).
"""
import os
import tempfile
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "web")]

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
            browser.page.set_content('''<!doctype html><title>Delayed client rendering test</title>
                <p>Local synthetic public widget</p><div style="height:1300px"></div>
                <button id="retired" aria-label="Show journey" aria-expanded="false">Details</button>
                <p id="details"></p>
                <script>window.addEventListener('scroll',()=>setTimeout(()=>{
                  const old=document.querySelector('#retired'); const fresh=old.cloneNode(true);
                  old.hidden=true; old.setAttribute('aria-hidden','true'); fresh.id='current';
                  fresh.removeAttribute('data-detour-ref');fresh.addEventListener('click',()=>{
                    fresh.setAttribute('aria-expanded','true');document.querySelector('#details').textContent='Segment details loaded';
                  });old.after(fresh);
                },30),{once:true});</script>''')
            page = browser.capture()
            disclosure = next(c for c in page['controls'] if c['label'] == 'Show journey')
            opened = browser.call('browser_click', {'ref': disclosure['ref']})
            assert 'Segment details loaded' in opened['text']
            assert opened['action']['outcome'] == 'CHANGED' and opened['action']['expandedAfter'] == 'true'
            assert browser.page.locator('#retired').evaluate('e=>e.isConnected')

            browser.page.set_content('''<button aria-label="Show details" aria-expanded="false">Details</button>''')
            page = browser.capture(); control = next(c for c in page['controls'] if c['tag'] == 'BUTTON')
            unchanged = browser.call('browser_click', {'ref': control['ref']})
            assert unchanged['action']['outcome'] == 'NO_CHANGE'

            browser.page.set_content('''<button aria-label="Unique control">Details</button>''')
            page = browser.capture(); control = next(c for c in page['controls'] if c['tag'] == 'BUTTON')
            browser.page.evaluate("()=>document.querySelector('button').setAttribute('aria-label','Changed control')")
            try:
                browser.call('browser_click', {'ref': control['ref']})
            except PlanningError as exc: assert 'changed' in str(exc)
            else: raise AssertionError('Semantic mutation must reject the captured reference')

            browser.page.set_content('''<button aria-label="Ambiguous control">Details</button>''')
            page = browser.capture(); control = next(c for c in page['controls'] if c['tag'] == 'BUTTON')
            browser.page.evaluate("()=>{const clone=document.querySelector('button').cloneNode(true);clone.removeAttribute('data-detour-ref');document.body.append(clone)}")
            try:
                browser.call('browser_click', {'ref': control['ref']})
            except PlanningError as exc: assert 'ambiguous' in str(exc)
            else: raise AssertionError('Fresh semantic resolution must reject ambiguity')

            browser.page.set_content('''<button aria-label="Book now">Continue</button>''')
            page = browser.capture(); control = next(c for c in page['controls'] if c['tag'] == 'BUTTON')
            try:
                browser.call('browser_click', {'ref': control['ref']})
            except PlanningError as exc: assert 'payment' in str(exc)
            else: raise AssertionError('A short visual label must not hide a transaction action')
            print('Passed: native widget selection, stale refs, delayed client rerender, semantic mutation/ambiguity rejection, observed disclosure outcome, and transaction guard; no network or user-trip writes.')
        finally:
            browser.close()
            if previous is None: os.environ.pop('PLANNER_DATA_DIR', None)
            else: os.environ['PLANNER_DATA_DIR'] = previous


if __name__ == '__main__': main()
