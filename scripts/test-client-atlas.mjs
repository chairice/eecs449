// Run after jac build main.jac: exercise the actual browser-emitted helpers.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { new_journey, clone_value, add_stop, update_stop, remove_stop,
  move_stop, set_leg_field, apply_proposal, search_places, validate_journey,
  load_atlas, write_atlas } from '../web/.jac/client/compiled/client/atlas_state.js';

const city = (id, name, state, county = '') => ({ id: `geo:${id}`, name, state, county,
  kind: 'CITY', lat: 42, lon: -83, code: '', aliases: [] });
const ann = city('1', 'Ann Arbor', 'MI', 'Washtenaw County');
const chicago = city('2', 'Chicago', 'IL', 'Cook County');
const springfield1 = city('3', 'Springfield', 'IL', 'Sangamon County');
const springfield2 = city('4', 'Springfield', 'MA', 'Hampden County');
const airport = { ...city('5', 'Detroit Metropolitan Airport', 'MI'), id: 'airport:5', kind: 'AIRPORT', code: 'DTW', aliases: ['KDTW'] };
const catalog = [ann, chicago, springfield1, springfield2, airport];
const key = 'detour.atlas.v1';

function journey() {
  let value = add_stop(add_stop(new_journey()));
  value.title = 'Midwest';
  value = update_stop(value, 0, ann, 'Ann Arbor, MI');
  value = update_stop(value, 1, chicago, 'Chicago, IL');
  return set_leg_field(value, 0, 'mode', 'DRIVE');
}

function storage(initial = null, failWrite = false) {
  let raw = initial;
  let writes = 0;
  globalThis.window = { localStorage: {
    getItem(name) { assert.equal(name, key); return raw; },
    setItem(name, value) { assert.equal(name, key); if (failWrite) throw new Error('quota'); writes++; raw = value; },
  }};
  load_atlas();
  return { raw: () => raw, writes: () => writes,
    replaceExternally(value) { raw = value; },
    failWrites(value) { failWrite = value; } };
}

test('fresh journeys and clones do not share nested arrays', () => {
  const first = new_journey(); const second = new_journey();
  first.stops.push({ query: 'x', place: null });
  assert.equal(second.stops.length, 0);
  const copy = clone_value(first); copy.stops[0].query = 'y';
  assert.equal(first.stops[0].query, 'x');
  assert.notEqual(first.id, second.id);
});

test('all itinerary mutations preserve input and invalidate affected routes', () => {
  let original = add_stop(journey());
  original = update_stop(original, 2, airport, 'DTW');
  original.legs.forEach(leg => { leg.route = { status: 'READY', points: [[42, -83], [41, -87]], message: '', source: 'test' }; });
  const edited = update_stop(original, 1, springfield1, 'Springfield, IL');
  assert.ok(edited.legs.every(leg => leg.route.status === 'UNROUTED'));
  assert.ok(original.legs.every(leg => leg.route.status === 'READY'));
  const removed = remove_stop(original, 1);
  assert.equal(removed.stops.length, 2); assert.equal(removed.legs.length, 1);
  assert.equal(removed.legs[0].route.status, 'UNROUTED');
  const reordered = move_stop(original, 0, 1);
  assert.equal(reordered.stops[0].place.id, chicago.id);
  assert.ok(reordered.legs.every(leg => leg.route.status === 'UNROUTED'));
  assert.equal(set_leg_field(original, 0, 'mode', 'FLIGHT').legs[0].route.status, 'UNROUTED');
  assert.equal(set_leg_field(original, 0, 'departDate', '2026-10-31').legs[0].route.status, 'READY');
  assert.deepEqual(move_stop(original, 0, -1), original);
});

test('search prioritizes exact airport codes, names, state and county disambiguation', () => {
  assert.equal(search_places(catalog, 'dtw')[0].id, airport.id);
  assert.equal(search_places(catalog, 'KDTW')[0].id, airport.id);
  assert.equal(search_places(catalog, 'Springfield, MA')[0].id, springfield2.id);
  assert.equal(search_places(catalog, 'Springfield Sangamon County IL')[0].id, springfield1.id);
  assert.equal(search_places(catalog, 'Ann A')[0].id, ann.id);
  assert.equal(search_places(catalog, 'Ann Arbor Michigan')[0].id, ann.id);
  assert.deepEqual(search_places(catalog, ''), []);
  assert.ok(search_places(Array.from({ length: 20 }, (_, i) => city(i, 'Example ' + i, 'MI')), 'Example').length <= 8);
});

test('moving or removing stops retains metadata only for unchanged ordered stop occurrences', () => {
  let original = add_stop(add_stop(journey()));
  original = update_stop(original, 2, airport, 'DTW');
  original = update_stop(original, 3, ann, 'Ann Arbor, MI');
  original.legs.forEach((leg, i) => Object.assign(leg, { mode: 'DRIVE', departDate: `2026-11-0${i + 1}`,
    arriveDate: `2026-11-0${i + 1}`, departTime: '09:00', arriveTime: '12:00', timingNote: `leg ${i}`,
    route: { status: 'READY', points: [[42, -83], [41, -87]], message: '', source: 'test' } }));
  const snapshot = structuredClone(original);
  const blank = add_stop(add_stop(new_journey())).legs[0];
  const moved = move_stop(original, 0, 1);
  assert.deepEqual(moved.legs[0], blank);
  assert.deepEqual(moved.legs[1], blank);
  assert.deepEqual(moved.legs[2], original.legs[2]);
  const removed = remove_stop(original, 1);
  assert.deepEqual(removed.legs[0], blank);
  assert.deepEqual(removed.legs[1], original.legs[2]);
  assert.deepEqual(remove_stop(original, 0).legs, original.legs.slice(1));
  assert.deepEqual(remove_stop(original, 3).legs, original.legs.slice(0, 2));
  assert.deepEqual(move_stop(original, 0, 0), original);
  // The returning Ann Arbor occurrence cannot borrow the outbound visit's leg.
  const returningFirst = move_stop(original, 3, -3);
  assert.deepEqual(returningFirst.legs[0], blank);
  assert.deepEqual(returningFirst.legs[1], original.legs[0]);
  assert.deepEqual(returningFirst.legs[2], original.legs[1]);
  assert.deepEqual(original, snapshot);
});

test('proposal application preserves identity, conversation and every unresolved stop', () => {
  const original = journey(); original.conversation = [{ role: 'user', content: 'Original request' }];
  const result = apply_proposal(original, { title: 'Changed', stops: ['Springfield', { name: 'Ann Arbor', state: 'MI' }, 'Toronto', 'DTW'], legs: [{ mode: 'DRIVE' }, { mode: 'UNKNOWN' }, { mode: 'FLIGHT' }], unresolved: ['Confirm travel mode'], originalText: 'Original request' }, catalog);
  assert.equal(result.id, original.id); assert.deepEqual(result.conversation, original.conversation);
  assert.equal(result.stops.length, 4); assert.equal(result.legs.length, 3);
  assert.equal(result.stops[0].place, null); assert.equal(result.stops[1].place.id, ann.id);
  assert.equal(result.stops[2].query, 'Toronto'); assert.equal(result.stops[2].place, null);
  assert.equal(result.stops[3].place.id, airport.id);
  assert.equal(result.originalText, 'Original request');
  assert.ok(validate_journey(result).length);
  assert.equal(original.title, 'Midwest');
});

test('incomplete or malformed proposals cannot partially overwrite a journey', () => {
  const original = journey(); original.note = 'My personal note';
  const complete = { title: 'Changed', stops: ['Ann Arbor MI', 'Chicago IL'], legs: [{ mode: 'DRIVE' }] };
  for (const proposal of [
    { title: 'Changed' }, { title: 'Changed', stops: ['Ann Arbor MI', 'Chicago IL'] },
    { ...complete, legs: [] }, { ...complete, stops: [] },
    { title: 'Changed', stops: [], legs: [] },
    { ...complete, stops: ['Ann Arbor MI', null] },
    { ...complete, stops: ['Ann Arbor MI', { query: 42 }] },
    { ...complete, stops: ['Ann Arbor MI', ''] },
    { ...complete, legs: [null] }, { ...complete, legs: [{ mode: 'BUS' }] },
    { ...complete, legs: [{ mode: 'DRIVE', departDate: 42 }] },
    { ...complete, title: {} }, { ...complete, unresolved: 'bad' },
    { ...complete, unresolved: ['x'.repeat(5001)] },
  ]) assert.deepEqual(apply_proposal(original, proposal, catalog), original);
  const applied = apply_proposal(original, { ...complete, note: 'AI replacement' }, catalog);
  assert.equal(applied.title, 'Changed'); assert.equal(applied.note, 'My personal note');
  const empty = new_journey();
  const fallback = apply_proposal(empty, { title: 'New journey', stops: [], legs: [], note: 'Unparsed request', unresolved: ['Review Unparsed request'] }, catalog);
  assert.equal(fallback.note, 'Unparsed request');
  assert.deepEqual(fallback.unresolved, ['Review Unparsed request']);
});

test('unchanged proposal queries retain manually disambiguated stop occurrences and road geometry', () => {
  const sameName1 = city('10', 'Springfield', 'MI', 'County One');
  const sameName2 = city('11', 'Springfield', 'MI', 'County Two');
  const duplicateCatalog = [sameName1, sameName2, chicago];
  let original = add_stop(add_stop(add_stop(new_journey())));
  original.title = 'Selected Springfields';
  original = update_stop(original, 0, sameName1, 'Springfield, MI');
  original = update_stop(original, 1, chicago, 'Chicago, IL');
  original = update_stop(original, 2, sameName2, 'Springfield, MI');
  original.legs.forEach((leg, i) => Object.assign(leg, { mode: 'DRIVE',
    route: { status: 'READY', points: [[42, -83], [41, -87]], message: `route ${i}`, source: 'OSRM' } }));
  const snapshot = structuredClone(original);
  const applied = apply_proposal(original, { title: 'Refined', stops: ['springfield Michigan', 'Chicago, IL', 'Springfield MI'],
    legs: [{ mode: 'DRIVE', departDate: '2026-11-01' }, { mode: 'DRIVE' }], unresolved: ['Review the refinement'] }, duplicateCatalog);
  assert.deepEqual(applied.stops.map(stop => stop.place.id), [sameName1.id, chicago.id, sameName2.id]);
  assert.deepEqual(applied.legs.map(leg => leg.route), original.legs.map(leg => leg.route));
  assert.equal(applied.legs[0].departDate, '2026-11-01');
  assert.deepEqual(original, snapshot);
  applied.legs[0].route.points[0][0] = 0;
  assert.equal(original.legs[0].route.points[0][0], 42);
  const extra = apply_proposal(original, { stops: ['Springfield MI', 'Chicago IL', 'Springfield MI', 'Springfield MI'],
    legs: [{ mode: 'DRIVE' }, { mode: 'DRIVE' }, { mode: 'DRIVE' }] }, duplicateCatalog);
  assert.equal(extra.stops[3].place, null); // Both previous user selections were consumed.
});

test('proposal routes require unchanged ordered endpoint IDs and mode and consume each old leg once', () => {
  const original = journey();
  original.legs[0].route = { status: 'READY', points: [[42, -83], [41, -87]], message: 'Keep me', source: 'OSRM' };
  for (const proposal of [
    { stops: ['Ann Arbor MI', 'DTW'], legs: [{ mode: 'DRIVE' }] },
    { stops: ['Chicago IL', 'Ann Arbor MI'], legs: [{ mode: 'DRIVE' }] },
    { stops: ['Ann Arbor MI', 'Chicago IL'], legs: [{ mode: 'FLIGHT' }] },
  ]) assert.equal(apply_proposal(original, proposal, catalog).legs[0].route.status, 'UNROUTED');
  const repeated = apply_proposal(original, { stops: ['Ann Arbor MI', 'Chicago IL', 'Ann Arbor MI', 'Chicago IL'],
    legs: [{ mode: 'DRIVE' }, { mode: 'DRIVE' }, { mode: 'DRIVE' }] }, catalog);
  assert.equal(repeated.legs[0].route.status, 'READY');
  assert.equal(repeated.legs[1].route.status, 'UNROUTED');
  assert.equal(repeated.legs[2].route.status, 'UNROUTED');
});

test('validation permits uncalculated routes but rejects malformed dates, modes and unresolved details', () => {
  assert.deepEqual(validate_journey(journey()), []);
  for (const [field, value] of [['departDate', '2026-02-30'], ['departTime', '25:00'], ['mode', 'UNKNOWN']]) {
    assert.ok(validate_journey(set_leg_field(journey(), 0, field, value)).length);
  }
  const dates = journey(); dates.legs[0].departDate = '2026-11-01'; dates.legs[0].arriveDate = '2026-10-31';
  assert.ok(validate_journey(dates).some(error => error.includes('Arrival')));
  const unresolved = journey(); unresolved.unresolved = ['Review dates'];
  assert.ok(validate_journey(unresolved).length);
  const past = journey(); past.status = 'PAST'; assert.deepEqual(validate_journey(past), []);
  assert.ok(validate_journey({}).length);
  assert.ok(validate_journey({ ...journey(), note: 'x'.repeat(8001) }).length);
});

test('one atomic write persists saved journeys and unresolved draft across reload', () => {
  const fixture = storage(); const saved = journey(); const draft = add_stop(new_journey());
  draft.stops[0].query = 'Unknown place';
  assert.equal(write_atlas([saved], draft), ''); assert.equal(fixture.writes(), 1);
  assert.deepEqual(load_atlas(), { journeys: [saved], draft, error: '' });
  assert.equal(write_atlas([saved], null), ''); assert.equal(load_atlas().draft, null);
});

test('an unsent prompt survives reload and remains optional for older records', () => {
  storage();
  const draft = new_journey();
  assert.equal(draft.pendingPrompt, '');
  draft.pendingPrompt = 'Fly from Detroit to Boston next summer';
  assert.equal(write_atlas([], draft), '');
  assert.equal(load_atlas().draft.pendingPrompt, draft.pendingPrompt);
  delete draft.pendingPrompt;
  assert.equal(write_atlas([], draft), '');
  assert.equal(load_atlas().error, '');
  for (const value of [null, 42, [], {}, 'x'.repeat(4001)]) {
    const malformed = { ...draft, pendingPrompt: value };
    const existing = JSON.stringify({ schemaVersion: 1, journeys: [], draft: malformed });
    const fixture = storage(existing);
    assert.ok(load_atlas().error);
    assert.ok(write_atlas([], new_journey()));
    assert.equal(fixture.raw(), existing);
    assert.equal(fixture.writes(), 0);
    storage();
    assert.ok(write_atlas([], malformed));
  }
});

test('corrupt, wrong-version and invalid stored data are preserved without writes', () => {
  for (const raw of ['bad json', '', '{}', '{"schemaVersion":2,"journeys":[],"draft":null}', JSON.stringify({ schemaVersion: 1, journeys: [{}], draft: null })]) {
    const fixture = storage(raw);
    assert.ok(load_atlas().error); assert.ok(write_atlas([journey()], null));
    assert.equal(fixture.raw(), raw); assert.equal(fixture.writes(), 0);
  }
});

test('quota failures and bad new records leave previous saved bytes intact', () => {
  const raw = JSON.stringify({ schemaVersion: 1, journeys: [journey()], draft: null });
  const full = storage(raw, true);
  assert.match(write_atlas([], null), /could not save/i); assert.equal(full.raw(), raw);
  const valid = storage(raw);
  assert.ok(write_atlas([new_journey()], null)); assert.equal(valid.raw(), raw);
  globalThis.window = { get localStorage() { throw new Error('blocked'); } };
  assert.ok(load_atlas().error); assert.ok(write_atlas([], null));
});

test('external changes block stale saves, draft autosaves, trash and restore writes', () => {
  const saved = journey();
  const original = JSON.stringify({ schemaVersion: 1, journeys: [saved], draft: null });
  const newer = { ...saved, title: 'Newer title from another tab' };
  const newerRaw = JSON.stringify({ schemaVersion: 1, journeys: [newer], draft: null });
  const draft = { ...saved, note: 'Keep these unsaved edits', pendingPrompt: 'And then go home' };
  const draftSnapshot = structuredClone(draft);
  const fixture = storage(original);
  fixture.replaceExternally(newerRaw);
  const trashed = { ...saved, deletedAt: '2026-10-30T12:00:00Z' };
  for (const [journeys, pendingDraft] of [
    [[saved], draft], [[draft], null], [[trashed], null], [[{ ...trashed, deletedAt: '' }], null],
  ]) {
    assert.match(write_atlas(journeys, pendingDraft), /changed in another tab/i);
    assert.equal(fixture.raw(), newerRaw);
    assert.equal(fixture.writes(), 0);
    assert.deepEqual(draft, draftSnapshot);
  }
  // Only an explicit reload adopts newer bytes; failed writes never do.
  assert.equal(load_atlas().journeys[0].title, newer.title);
  assert.equal(write_atlas([newer], draft), '');
  assert.equal(fixture.writes(), 1);
});

test('snapshot detects external creation, deletion and corruption and advances only after own success', () => {
  const saved = journey();
  const raw = JSON.stringify({ schemaVersion: 1, journeys: [saved], draft: null });
  for (const [initial, external] of [[null, raw], [raw, null], [raw, 'corrupt']]) {
    const fixture = storage(initial); fixture.replaceExternally(external);
    assert.match(write_atlas([], null), /changed in another tab/i);
    assert.equal(fixture.raw(), external); assert.equal(fixture.writes(), 0);
  }
  const fixture = storage(raw, true);
  assert.match(write_atlas([saved], new_journey()), /could not save/i);
  fixture.failWrites(false);
  // A quota error did not advance the snapshot to the failed attempted bytes.
  assert.equal(write_atlas([saved], null), '');
  assert.equal(write_atlas([saved], new_journey()), '');
  assert.equal(fixture.writes(), 2);
});

test('bundled primary-source catalog covers exactly 50 states and DC, with checked bytes', () => {
  const dir = new URL('../web/fixtures/atlas/', import.meta.url);
  const manifest = JSON.parse(readFileSync(new URL('manifest.json', dir)));
  for (const [name, expected] of Object.entries(manifest.outputs)) {
    const bytes = readFileSync(new URL(name, dir));
    assert.equal(bytes.length, expected.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), expected.sha256);
  }
  const records = JSON.parse(gunzipSync(readFileSync(new URL('places.json.gz', dir))));
  const allowed = 'AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY'.split(' ').sort();
  assert.deepEqual([...new Set(records.map(place => place.state))].sort(), allowed);
  assert.equal(new Set(records.map(place => place.id)).size, records.length);
  assert.equal(records.length, manifest.catalog.places);
  const states = JSON.parse(readFileSync(new URL('states.geojson', dir)));
  assert.deepEqual(states.features.map(feature => feature.properties.code).sort(), allowed);
  assert.ok(search_places(records, 'Honolulu').some(place => place.state === 'HI'));
  assert.ok(search_places(records, 'Anchorage').some(place => place.state === 'AK'));
  assert.equal(search_places(records, 'DTW')[0].kind, 'AIRPORT');
});
