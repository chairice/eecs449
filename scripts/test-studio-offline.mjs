import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../web/.jac/client/dist/sw.js', import.meta.url), 'utf8');
function worker(offline = false) {
  const handlers = {}, writes = [], deleted = [];
  const context = {
    URL, Promise, Response,
    self: {location: {origin: 'https://atlas.example'}, addEventListener: (name, fn) => handlers[name] = fn,
      skipWaiting: async () => {}, clients: {claim: async () => {}}},
    caches: {open: async () => ({addAll: async assets => writes.push(...assets)}),
      keys: async () => ['atlas-studio-old', 'other-app-cache'], delete: async key => deleted.push(key),
      match: async request => {
        if(request==='./index.html')return 'APP_SHELL';
        const response=new Response('CACHED_ASSET',{headers:{'Content-Type':'text/javascript'}});
        Object.defineProperty(response,'url',{value:new URL(request,'https://atlas.example/').href});
        return response;
      }},
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
  assert.equal(await (await value.request('/styles.css?hash=build')).text(), 'CACHED_ASSET');
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

test('locally bundled airline marks are available offline without caching their provenance or remote images', async () => {
  const value = worker(true);
  assert.equal(await (await value.request('/static/assets/airlines/f9.png')).text(), 'CACHED_ASSET');
  assert.equal(value.request('/static/assets/airlines/sources.json'), undefined);
  assert.equal(value.request('https://www.gstatic.com/flights/airline_logos/70px/F9.png'), undefined);
});

test('a first offline PDF export resolves Vite lazy chunks through their exact precached Jac asset alias', async () => {
  const value=worker(true),installed=worker();
  let pending;installed.handlers.install({waitUntil:promise=>pending=promise});await pending;
  const pdf=installed.writes.find(name=>/^\.\/static\/assets\/trip_pdf_render-.*\.js$/.test(name));
  assert.ok(pdf,'The PDF renderer and embedded fonts must be precached before any export.');
  const cached=await value.request(pdf.replace('./static/','/'));
  assert.equal(await cached.text(),'CACHED_ASSET');
  assert.equal(cached.url,'','Alias responses must retain the request URL as the module base, not /static/assets/.');
  assert.equal(cached.headers.get('Content-Type'),'text/javascript');
  assert.equal(value.request('/assets/not-in-this-build.js'),undefined);
  assert.equal(value.request('/assets/airlines/sources.json'),undefined);
});
