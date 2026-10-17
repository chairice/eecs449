// Run after `jac build main.jac` in web/. Tests the actual emitted Jac adapter.
// No running server, browser, credentials, or network access required.
import assert from 'node:assert/strict';
import test from 'node:test';
import { comparison_view } from '../web/.jac/client/compiled/components/comparison_view.js';

function preview() {
  return {
    schema_version: 1,
    mode: 'FIXTURE',
    as_of: '2026-10-23T18:00:00Z',
    request: {
      origin_text: 'Ann Arbor', destination_text: 'Chicago',
      local_date: '2026-10-23', priority: 'BALANCED',
    },
    error: null,
    routes: [{
      score: 70,
      reason_codes: ['LOWEST_COST', 'MISSING_DATA'],
      risk: { delay: 'UNKNOWN', weather: 'UNKNOWN', transfer: 'LOW' },
      option: {
        id: 'sample-route', price_cents: 3850, currency: 'USD',
        source: {
          provider: 'unit-test-synthetic-provider', status: 'FIXTURE',
          fetched_at: '2026-10-17T00:00:00Z', expires_at: null,
          warnings: [{ code: 'SYNTHETIC_DATA', message: 'Synthetic examples only.' }],
        },
        legs: [{
          id: 'sample-leg', mode: 'BUS', service: 'Example bus',
          origin: { name: 'Ann Arbor', timezone: 'America/Detroit' },
          destination: { name: 'Chicago', timezone: 'America/Chicago' },
          departure_at: '2026-10-23T16:00:00-04:00',
          arrival_at: '2026-10-23T18:00:00-05:00',
        }],
      },
    }],
  };
}

test('actual emitted adapter formats canonical facts and grounded reasons', () => {
  const view = comparison_view(preview());
  assert.equal(view.valid, true);
  assert.equal(view.title, 'Ann Arbor → Chicago');
  assert.equal(view.routes[0].duration, '3h 0m');
  assert.equal(view.routes[0].price, '$38.50 USD');
  assert.equal(view.routes[0].score, '70.0');
  assert.match(view.routes[0].departure, /4:00 PM/);
  assert.match(view.routes[0].arrival, /6:00 PM/);
  assert.equal(view.routes[0].delay, 'Unknown');
  assert.equal(view.routes[0].weather, 'Unknown');
  assert.equal(view.routes[0].source, 'FIXTURE');
  assert.equal(view.routes[0].freshness, 'Synthetic example');
  assert.deepEqual(view.routes[0].reasons, [
    'Lowest known fare among these options',
    'Some fare, delay, or weather information is unknown',
  ]);
});

test('route order stays exactly as supplied by server ranking', () => {
  const data = preview();
  const second = structuredClone(data.routes[0]);
  second.option.id = 'second'; second.score = 100;
  data.routes.push(second);
  assert.deepEqual(comparison_view(data).routes.map(route => route.id), ['sample-route', 'second']);
});

test('missing fare remains distinct from free', () => {
  const data = preview();
  data.routes[0].option.price_cents = null;
  assert.equal(comparison_view(data).routes[0].price, 'Fare unavailable');
  data.routes[0].option.price_cents = 0;
  assert.equal(comparison_view(data).routes[0].price, '$0.00 USD');
});

test('missing timestamps and freshness never claim live data is current', () => {
  const data = preview();
  const source = data.routes[0].option.source;
  source.fetched_at = null;
  assert.equal(comparison_view(data).routes[0].source_time, 'Timestamp unavailable');
  delete source.fetched_at;
  assert.equal(comparison_view(data).routes[0].source_time, 'Timestamp unavailable');
  source.status = 'CACHED';
  assert.equal(comparison_view(data).routes[0].freshness, 'Freshness unknown');
  source.fetched_at = '2026-10-23T17:00:00Z';
  source.status = 'LIVE';
  assert.equal(comparison_view(data).routes[0].freshness, 'Freshness unknown');
  source.expires_at = '2026-10-23T19:00:00Z';
  assert.equal(comparison_view(data).routes[0].freshness, 'Current at search');
  source.expires_at = data.as_of;
  assert.match(comparison_view(data).routes[0].freshness, /stale/);
});

test('no preview and valid no-route envelopes recover without inventing results', () => {
  assert.equal(comparison_view(null).valid, false);
  assert.equal(comparison_view(undefined).valid, false);
  const data = preview(); data.routes = [];
  assert.equal(comparison_view(data).error_code, 'NO_ROUTES');
  data.error = { code: 'PROVIDER_UNAVAILABLE', message: 'Try this search again.' };
  assert.equal(comparison_view(data).error, 'Try this search again.');
  assert.equal(comparison_view(data).routes.length, 0);
});

test('malformed nested data and invalid primitives recover rather than crash', () => {
  const mutations = [
    data => { data.routes = null; },
    data => { data.routes[0].option = null; },
    data => { data.routes[0].option.legs = []; },
    data => { data.routes[0].option.legs[0].origin = null; },
    data => { data.routes[0].option.legs[0].departure_at = 'bad time'; },
    data => { data.routes[0].option.legs[0].origin.timezone = 'Invalid/Zone'; },
    data => { data.routes[0].option.price_cents = true; },
    data => { data.routes[0].option.price_cents = -1; },
    data => { data.routes[0].score = NaN; },
    data => { data.routes[0].risk.weather = 'SAFE'; },
    data => { data.routes.push(structuredClone(data.routes[0])); },
  ];
  for (const mutate of mutations) {
    const data = preview(); mutate(data);
    const view = comparison_view(data);
    assert.equal(view.valid, false);
    assert.equal(view.error_code, 'INVALID_PREVIEW');
  }
});

test('time zones are explicit and daylight saving offsets do not change duration', () => {
  const data = preview();
  const leg = data.routes[0].option.legs[0];
  leg.departure_at = '2026-11-01T01:30:00-04:00';
  leg.arrival_at = '2026-11-01T01:30:00-06:00';
  assert.equal(comparison_view(data).routes[0].duration, '2h 0m');
});
