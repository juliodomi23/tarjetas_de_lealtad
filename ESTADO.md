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
- **Clave dueño vs personal**: campo `staff_pass` opcional por negocio (se
  define en Configuración del panel). Solo sirve para sellar/canjear; el panel
  sigue pidiendo la clave del dueño.
- **Webhook n8n**: con `WEBHOOK_URL` en el entorno, `/api/stamp` avisa (POST,
  fire-and-forget) cuando un cliente gana premio. Payload en `DEPLOY.md`.
- **Backup**: script versionado `backup.sh` + cron documentado en `DEPLOY.md`.
- **Tests**: `npm test` corre `test.js` (unitario de db.js) y `test-http.js`
  (integración HTTP contra el server real: auth, staff_pass, sellos, canje,
  no-filtración de claves). En verde.
- **Deploy**: PM2 + nginx + certbot en VPS (ver `DEPLOY.md`). Producción:
  `https://lealtad.ambarrojostudios.cloud`.

---

## Backlog (prioridad sugerida)

| # | Qué | Por qué | Esfuerzo |
|---|-----|---------|----------|
| 1 | **Workflow n8n del aviso WhatsApp** | El server ya dispara el webhook (`WEBHOOK_URL`); falta crear el workflow en n8n que reciba y mande el mensaje. | Bajo |
| 2 | **Configurar cron de backup en el VPS** | El script `backup.sh` ya está; falta agregar la línea al crontab (ver `DEPLOY.md`). | Bajo |
| 3 | **Rate-limit persistente** | Hoy en memoria (`Map` por proceso); pasar a `express-rate-limit` si se escala a varios procesos. Marcado con `ponytail:` en `server.js`. | Bajo |
| 4 | **Caché offline en `sw.js`** | El SW solo habilita la instalación PWA. Marcado con `ponytail:` en `sw.js`. | Bajo |

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
