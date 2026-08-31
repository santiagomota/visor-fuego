const VISOR_FUEGO_SW_VERSION = "0.6.25";

self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key.startsWith("visor-fuego-"))
        .map((key) => caches.delete(key))
    );
    await self.clients.claim();
  })());
});

function cacheBustedUrl(input) {
  const url = new URL(input);
  url.searchParams.set("_vf_sw", VISOR_FUEGO_SW_VERSION + "-" + Date.now());
  return url.toString();
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isNavigation =
    request.mode === "navigate" ||
    request.destination === "document";

  const isRuntimeAsset =
    url.pathname.includes("/assets/") &&
    /\.(json|geojson|csv)$/i.test(url.pathname);

  if (!isNavigation && !isRuntimeAsset) return;

  event.respondWith((async () => {
    try {
      return await fetch(cacheBustedUrl(url.toString()), {
        cache: "no-store",
        credentials: "same-origin",
        redirect: "follow"
      });
    } catch (error) {
      return fetch(request);
    }
  })());
});
