// Service worker mínimo: solo habilita la instalación como app (PWA).
// ponytail: sin caché offline todavía; agregar cache-first si se quiere uso sin red.
self.addEventListener('fetch', () => {});
