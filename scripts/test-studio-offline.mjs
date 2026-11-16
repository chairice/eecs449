import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../web/.jac/client/dist/sw.js', import.meta.url), 'utf8');
function worker(offline = false) {
  const handlers = {}, writes = [], deleted = [];
  const context = {
    URL, Promise,
    self: {location: {origin: 'https://atlas.example'}, addEventListener: (name, fn) => handlers[name] = fn,
      skipWaiting: async () => {}, clients: {claim: async () => {}}},
    caches: {open: async () => ({addAll: async assets => writes.push(...assets)}),
      keys: async () => ['atlas-studio-old', 'other-app-cache'], delete: async key => deleted.push(key),
      match: async request => request === './index.html' ? 'APP_SHELL' : 'CACHED_ASSET'},
    fetch: async () => {if (offline) throw new Error('offline'); return 'NETWORK';},
  };
  vm.runInNewContext(source, context);
  function request(path, {method = 'GET', mode = 'cors'} = {}) {
    let response;
    handlers.fetch({request: {url: new URL(path, 'https://atlas.example').href, method, mode},
      respondWith: promise => response = promise});
    return response;
  }
  return {handlers, writes, deleted, request};
}

test('offline root and studio navigations reopen the cached application shell', async () => {
  const value = worker(true);
  assert.equal(await value.request('/studio', {mode: 'navigate'}), 'APP_SHELL');
  assert.equal(await value.request('/', {mode: 'navigate'}), 'APP_SHELL');
  assert.equal(await value.request('/styles.css?hash=build'), 'CACHED_ASSET');
});

test('account APIs, uploads, external map tiles and arbitrary pages bypass the offline cache', () => {
  const value = worker(true);
  for (const path of ['/function/planner_get', '/user/login', '/api/trips', '/walker/trip', '/healthz',
    'https://tile.openstreetmap.org/1/1/1.png', '/unrelated']) {
    assert.equal(value.request(path), undefined, path);
  }
  assert.equal(value.request('/function/planner_approve', {method: 'POST'}), undefined);
});

test('installation caches only application assets and activation preserves other apps caches', async () => {
  const value = worker();
  let pending;
  value.handlers.install({waitUntil: promise => pending = promise}); await pending;
  assert.ok(value.writes.includes('./index.html'));
  assert.ok(value.writes.some(name => /^\.\/client\..*\.js$/.test(name)));
  assert.ok(value.writes.every(name => name.startsWith('./') && !name.startsWith('./function/')));
  value.handlers.activate({waitUntil: promise => pending = promise}); await pending;
  assert.deepEqual(value.deleted, ['atlas-studio-old']);
});
