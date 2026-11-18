'use strict';

const PREFIX = 'trajectory-';
const CACHE = PREFIX + 'sqlite-v6';
const INDEX = new URL('./index.html', self.registration.scope).href;
const HOME = new URL('./', self.registration.scope).href;
const ASSETS = [
  './',
  'style.css',
  'engine.js',
  'app.js',
  'charts.js',
  'retirement.js',
  'planner.js',
  'storage.js',
  'manifest.webmanifest',
  'icon-192.png',
  'icon-512.png',
  'vendor/sql-wasm.js',
  'vendor/sql-wasm.wasm'
].map(path => new URL(path, HOME).href);

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    const files = await Promise.all(ASSETS.map(async url => {
      const response = await fetch(url, { cache: 'reload' });
      const type = response.headers.get('content-type') || '';
      if (!response.ok || response.redirected ||
          (type.includes('text/html') && url !== HOME)) {
        throw new Error('Cannot cache app asset: ' + url);
      }
      return [url, response];
    }));
    await Promise.all(files.map(([url, response]) => cache.put(url, response)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    const previous = keys.filter(key => key.startsWith(PREFIX) && key !== CACHE);
    await Promise.all(previous.map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  const page = event.request.mode === 'navigate' &&
    (url.origin + url.pathname === HOME || url.origin + url.pathname === INDEX);
  const asset = page ? HOME : url.href;
  if (!ASSETS.includes(asset)) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    return await cache.match(asset) || fetch(event.request);
  })());
});
