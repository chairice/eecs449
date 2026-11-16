// Filled by scripts/finalize-studio-build.py after Jac's production build.
const CACHE_NAME = 'atlas-studio-__BUILD_ID__';
const PRECACHE_ASSETS = __PRECACHE_ASSETS__;

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME)
    .then(cache => cache.addAll(PRECACHE_ASSETS))
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys()
    .then(names => Promise.all(names.filter(name => name.startsWith('atlas-studio-') && name !== CACHE_NAME)
      .map(name => caches.delete(name))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  // Account responses, research, uploads and map tiles never enter this cache.
  if (request.method !== 'GET' || url.origin !== self.location.origin ||
      /^\/(api|function|walker|user|healthz)(\/|$)/.test(url.pathname)) return;
  if (request.mode === 'navigate' && (url.pathname === '/' || url.pathname === '/studio')) {
    event.respondWith(fetch(request).catch(() => caches.match('./index.html')));
    return;
  }
  const relative = '.' + url.pathname;
  if (PRECACHE_ASSETS.includes(relative)) {
    // Jac appends a content hash query to its stylesheet URL.
    event.respondWith(caches.match(relative).then(cached => cached || fetch(request)));
  }
});
