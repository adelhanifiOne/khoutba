// Service worker : rend l'app utilisable hors-ligne (à la mosquée).
// Stratégie : cache d'abord pour les fichiers de l'app ; le réseau n'est
// utilisé que pour les API d'IA (jamais mises en cache).

// ⚠️ Incrémenter à chaque mise en ligne : c'est ce qui déclenche la mise à
// jour des fichiers sur les téléphones où l'app est déjà installée.
const CACHE = 'khoutba-v8';

const FICHIERS = [
  './',
  './index.html',
  './css/app.css',
  './js/app.js',
  './js/db.js',
  './js/recorder.js',
  './js/providers.js',
  './js/pipeline.js',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FICHIERS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then(cles => Promise.all(cles.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const { request } = e;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== location.origin) return; // API externes : réseau direct

  e.respondWith(
    caches.match(request, { ignoreSearch: true }).then(reponse => {
      if (reponse) return reponse;
      return fetch(request).then(rep => {
        if (rep.ok) {
          const copie = rep.clone();
          caches.open(CACHE).then(c => c.put(request, copie));
        }
        return rep;
      });
    })
  );
});
