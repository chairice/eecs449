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
  let relative = '.' + url.pathname;
  // Vite's lazy imports use /assets/; Jac also serves that same directory at
  // /static/assets/, which is the canonical precache URL. Only alias files
  // explicitly present in this build's allowlist, never arbitrary requests.
  if (url.pathname.startsWith('/assets/')) {
    const canonical = './static' + url.pathname;
    if (PRECACHE_ASSETS.includes(canonical)) relative = canonical;
  }
  if (PRECACHE_ASSETS.includes(relative)) {
    // Includes local carrier marks at /static/assets/; source metadata, API
    // responses and remote images remain outside the application cache.
    // Jac appends a content hash query to its stylesheet URL.
    event.respondWith(caches.match(relative).then(cached => {
      if (!cached) return fetch(request);
      // A cached response's URL normally becomes an ES module's base URL. For
      // an alias, retain the requested /assets/ base so ../client.js imports
      // resolve correctly, instead of becoming /static/client.js.
      return relative !== '.' + url.pathname
        ? new Response(cached.body, {status: cached.status, statusText: cached.statusText, headers: cached.headers})
        : cached;
    }));
  }
});
