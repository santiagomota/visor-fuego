const VISOR_FUEGO_SW_VERSION = "0.6.32";
const VISOR_FUEGO_SCOPE_PATH = "/visor-fuego/";

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

    // Permite que el worker controle inmediatamente pestañas ya abiertas.
    await self.clients.claim();
  })());
});

function cacheBustedUrl(input) {
  const url = new URL(input);
  url.searchParams.set(
    "_vf_sw",
    VISOR_FUEGO_SW_VERSION + "-" + Date.now()
  );
  return url.toString();
}

function isInsideVisor(url) {
  return (
    url.origin === self.location.origin &&
    url.pathname.startsWith(VISOR_FUEGO_SCOPE_PATH)
  );
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (!isInsideVisor(url)) return;

  const isNavigation =
    request.mode === "navigate" ||
    request.destination === "document";

  const isRuntimeAsset =
    url.pathname.includes("/assets/") &&
    /\.(json|geojson|csv)$/i.test(url.pathname);

  if (!isNavigation && !isRuntimeAsset) return;

  event.respondWith((async () => {
    const busted = cacheBustedUrl(url.toString());

    try {
      const response = await fetch(busted, {
        cache: "no-store",
        credentials: "same-origin",
        redirect: "follow",
        headers: {
          "Cache-Control": "no-cache, no-store, max-age=0",
          "Pragma": "no-cache"
        }
      });

      if (!response.ok) {
        throw new Error("HTTP " + response.status);
      }

      return response;
    } catch (error) {
      // Solo como recuperación de red. Nunca escribimos respuestas en CacheStorage.
      return fetch(request, { cache: "reload" });
    }
  })());
});
