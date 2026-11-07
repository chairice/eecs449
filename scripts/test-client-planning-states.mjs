// Run after `jac build main.jac` in web/. Fixture-driven tests of every planning
// state the results flow renders: loading, no routes, provider failure, stale
// and partial data, and duplicate-safe saving. Each state's words and ARIA role
// come from these emitted modules, which the components render as-is.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { comparison_view } from '../web/.jac/client/compiled/components/comparison_view.js';
import { SLOW_AFTER_MS, data_notices, plan_trip_id, planning_outcome, planning_progress }
  from '../web/.jac/client/compiled/client/planning_states.js';

const fixture = name => JSON.parse(readFileSync(new URL(`../web/fixtures/states/${name}.json`, import.meta.url), 'utf8'));
const outcomeOf = name => planning_outcome(comparison_view(fixture(name)));

test('loading names the running phase and never shows a percentage', () => {
  const reading = planning_progress('understanding', 0);
  assert.equal(reading.phase, 'Understanding the request');
  assert.deepEqual(reading.steps.map(step => step.state), ['current', 'waiting', 'waiting']);
  const routes = planning_progress('routes', 500);
  assert.match(routes.phase, /Checking routes/);
  assert.deepEqual(routes.steps.map(step => step.state), ['done', 'current', 'current']);
  assert.match(planning_progress('return', 0).phase, /return routes/);
  for (const stage of ['understanding', 'routes', 'return']) {
    for (const elapsed of [0, 9999, 10000, 60000]) {
      assert.doesNotMatch(planning_progress(stage, elapsed).message, /\d+\s*%/);
    }
  }
});

test('the longer-wait message appears at ten seconds, not before', () => {
  assert.equal(SLOW_AFTER_MS, 10000);
  const early = planning_progress('routes', 9999);
  assert.equal(early.slow, false);
  assert.doesNotMatch(early.message, /longer than expected/);
  const late = planning_progress('routes', 10000);
  assert.equal(late.slow, true);
  assert.match(late.message, /External data is taking longer than expected/);
  assert.match(late.message, /cancel/i);
});

test('no routes explains which constraints removed candidates and stays a calm status', () => {
  const view = comparison_view(fixture('no-routes'));
  assert.equal(view.error_code, 'NO_ROUTES');
  assert.deepEqual(view.rejections, [
    'Over your maximum price: 2 routes',
    'A connection shorter than your 45-minute buffer: 1 route',
    'Outside your travel time: 1 route',
  ]);
  assert.equal(view.suggestion, 'Raise or remove the maximum price.');
  const outcome = planning_outcome(view);
  assert.equal(outcome.kind, 'no_routes');
  assert.equal(outcome.role, 'status');
  assert.equal(outcome.retry, false);
  assert.ok(outcome.details.includes('Suggestion: Raise or remove the maximum price.'));
});

test('provider failure is distinct from no routes: an alert with retry', () => {
  const failed = outcomeOf('provider-error');
  const empty = outcomeOf('no-routes');
  assert.equal(failed.kind, 'provider_error');
  assert.equal(failed.role, 'alert');
  assert.equal(failed.retry, true);
  assert.match(failed.message, /not a no-routes result/);
  assert.notEqual(failed.title, empty.title);
  assert.notEqual(failed.role, empty.role);
  assert.deepEqual(failed.details, []);
});

test('an unreadable result alerts and offers retry; no request is a quiet empty state', () => {
  const unreadable = planning_outcome(comparison_view({ schema_version: 2 }));
  assert.equal(unreadable.kind, 'invalid');
  assert.equal(unreadable.role, 'alert');
  assert.equal(unreadable.retry, true);
  const empty = planning_outcome(comparison_view(null));
  assert.equal(empty.kind, 'empty');
  assert.equal(empty.role, 'status');
});

test('stale routes stay usable only with freshness and provenance labels', () => {
  const view = comparison_view(fixture('stale-routes'));
  assert.equal(planning_outcome(view).kind, 'ready');
  assert.equal(view.routes.length, 1);
  assert.equal(view.stale, true);
  const route = view.routes[0];
  assert.match(route.freshness, /Out of date · stale/);
  assert.equal(route.provider, 'detour-synthetic-corridor-v1');
  assert.match(route.source_time, /Oct 23, 2026/);
  assert.deepEqual(route.source_warnings, ['Schedules were fetched six hours ago.']);
  const routes = view.sources.find(line => line.kind === 'routes');
  assert.equal(routes.provider, 'Detour synthetic schedules');
  assert.equal(routes.status, 'Cached · out of date');
  assert.equal(routes.stale, true);
  const notices = data_notices(view);
  assert.deepEqual(notices.map(notice => notice.kind), ['stale']);
  assert.equal(notices[0].retry, true);
});

test('weather unavailable keeps ranking with weather unknown, never safe', () => {
  const view = comparison_view(fixture('weather-unavailable'));
  assert.equal(planning_outcome(view).kind, 'ready');
  assert.equal(view.weather_checked, true);
  assert.equal(view.weather_unavailable, true);
  assert.equal(view.routes[0].weather, 'Unknown');
  assert.match(view.routes[0].weather_note, /unknown, not clear/);
  const notice = data_notices(view).find(item => item.kind === 'weather_unavailable');
  assert.ok(notice);
  assert.equal(notice.retry, true);
  assert.match(notice.message, /Unknown is not the same as clear/);
  assert.equal(view.sources.find(line => line.kind === 'weather').status, 'Unavailable');
});

test('a search without a weather source says weather was not checked', () => {
  const data = fixture('weather-unavailable');
  data.sources = data.sources.slice(0, 1);
  const view = comparison_view(data);
  assert.equal(view.weather_checked, false);
  assert.deepEqual(data_notices(view).map(notice => notice.kind), ['weather_unchecked']);
});

test('saving the same plan twice yields one ID, so retries cannot duplicate it', () => {
  const parts = ['Ann Arbor → Chicago', 'Fri, Oct 23', 'demo-train', ''];
  assert.equal(plan_trip_id(parts), plan_trip_id([...parts]));
  assert.match(plan_trip_id(parts), /^trip-[0-9a-z]+-[0-9a-z]+$/);
  assert.notEqual(plan_trip_id(parts), plan_trip_id(['Ann Arbor → Chicago', 'Fri, Oct 23', 'cached-bus', '']));
  assert.notEqual(plan_trip_id(parts), plan_trip_id(['Ann Arbor → Chicago', 'Fri, Oct 23', 'demo-train', 'return-1']));
});
