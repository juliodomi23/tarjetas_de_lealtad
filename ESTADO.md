# Estado del proyecto — Tarjetas de lealtad (Aurum)

Documento de traspaso. Quien continúe: lee esto y el `README.md`.

**Última actualización:** 2026-07-15

---

## Qué está listo y funcionando

- **Multi-tenant**: varios negocios en un deploy (tabla `businesses`, slug por
  request, aislamiento probado en `test.js`).
- **Backend** (`server.js` + `db.js`, Express + SQLite): registro, sellos con
  cooldown de 120s, recompensas multi-tier con reset de ciclo, **canje de
  premios** (`POST /api/redeem`, columna `redeemed_rewards`), claves scrypt,
  rate-limit anti fuerza bruta y anti-spam en `/api/join`.
- **Wallets**: Apple (.pkpass) y Google (JWT) en `wallet.js`; se activan solo si
  hay certs/env vars, si no los botones se ocultan.
- **Web** (`public/`): `join.html` (registro + tarjeta + QR + PWA instalable),
  `admin.html` (login, KPIs, gráfica, clientes con canje y **export CSV**,
  recompensas, branding), `superadmin.html` (alta/edición de negocios),
  `landing.html`, `privacidad.html`.
- **App Flutter** (`flutter_app/`): tarjetas del cliente (multi-negocio),
  escáner nativo del personal, panel admin con canje de premios. `apiBase`
  configurable con `--dart-define=API_BASE=...`. `flutter analyze`: solo 3
  infos preexistentes.
- **Tests**: `npm test` (`test.js`) — claves, join, ciclo de sellos, cooldown,
  stats, aislamiento multi-tenant y canje. En verde.
- **Deploy**: PM2 + nginx + certbot en VPS (ver `DEPLOY.md`). Producción:
  `https://lealtad.ambarrojostudios.cloud`.

---

## Backlog (prioridad sugerida)

| # | Qué | Por qué | Esfuerzo |
|---|-----|---------|----------|
| 1 | **Aviso por WhatsApp al ganar premio** | `/api/stamp` ya devuelve `earned`; enganchar a un workflow n8n (stack de Ámbar Rojo). | Medio |
| 2 | **Clave separada dueño vs personal** | Hoy comparten `admin_pass` por negocio. | Bajo |
| 3 | **Respaldo automatizado de la SQLite** | Hoy es un cron manual en el VPS (`DEPLOY.md`); versionar el script y verificar que corra. | Bajo |
| 4 | **Rate-limit persistente** | Hoy en memoria (`Map` por proceso); pasar a `express-rate-limit` si se escala a varios procesos. Marcado con `ponytail:` en `server.js`. | Bajo |
| 5 | **Tests HTTP de `server.js`** | `test.js` solo cubre `db.js`. | Medio |
| 6 | **Caché offline en `sw.js`** | El SW solo habilita la instalación PWA. Marcado con `ponytail:` en `sw.js`. | Bajo |

---

## Notas técnicas para quien continúe

- **WhatsApp / prefijo:** web y app anteponen `52` solo a números de 10 dígitos
  (formato local MX); números con lada se usan tal cual.
- **Normalización de teléfono** (`db.js`, `normPhone`): solo quita no-dígitos.
  Para `+52`/`521` puede hacer falta calibrar si aparecen duplicados.
- **PWA**: `manifest.json` → `join.html`; sin `?b=` usa el último negocio
  visitado (`localStorage.aurum_last_slug`).
- Para probar con datos: `DB_FILE` de prueba, registra vía `/api/join`, sella
  vía `/api/stamp`, canjea vía `/api/redeem`.
- App Flutter contra server local: `flutter run --dart-define=API_BASE=http://10.0.2.2:3000`.
