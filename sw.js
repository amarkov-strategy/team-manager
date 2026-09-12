/* Team Manager service worker
   ----------------------------
   Strategy:
   - HTML navigations  → network-first (always pick up the latest
     index.html when online, fall back to cache when offline)
   - Static assets     → cache-first (instant loads, refreshed on
     next online visit)
   - Pantry API calls  → bypassed entirely so syncs never get stuck
     on a stale cached response
*/
const CACHE = 'tm-cache-v23-backup-restore';

const PRECACHE = [
  './',
  './index.html',
  './TeamManager.png',
  './LilCardinalsLogo.png',
  './LilCardinalFavicon.png',
  './logo.svg',
  './manifest.json'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      cache.addAll(PRECACHE).catch(() => {})
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (e) { return; }

  // Never cache the sync API — needs to be live.
  if (url.hostname === 'getpantry.cloud') return;
  // Cross-origin CDN fonts/icons keep their own caching headers; skip.
  if (url.origin !== self.location.origin) return;

  const isNav = req.mode === 'navigate' ||
                (req.destination === 'document') ||
                (req.headers.get('accept') || '').includes('text/html');

  if (isNav) {
    // Network-first for HTML
    event.respondWith(
      fetch(req).then((resp) => {
        if (resp && resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE).then((c) => c.put(req, clone)).catch(() => {});
        }
        return resp;
      }).catch(() =>
        caches.match(req).then((cached) => cached || caches.match('./index.html') || caches.match('./'))
      )
    );
    return;
  }

  // Cache-first for assets
  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((resp) => {
        if (resp && resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE).then((c) => c.put(req, clone)).catch(() => {});
        }
        return resp;
      }).catch(() => cached);
    })
  );
});
