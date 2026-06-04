// Timegrapher service worker — cache-first for app shell, network for everything else.
const CACHE = 'timegrapher-v2';
const ASSETS = [
  './', './index.html', './manifest.webmanifest',
  './assets/icon.svg', './assets/icon-192.png', './assets/icon-512.png',
  './assets/apple-touch-icon.png', './assets/favicon-32.png', './assets/og-image.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  e.respondWith(
    caches.match(req).then((hit) => hit || fetch(req).then((resp) => {
      // opportunistically cache same-origin GET responses
      const url = new URL(req.url);
      if (url.origin === self.location.origin && resp.ok) {
        const clone = resp.clone();
        caches.open(CACHE).then((c) => c.put(req, clone)).catch(() => {});
      }
      return resp;
    }).catch(() => caches.match('./index.html')))
  );
});
