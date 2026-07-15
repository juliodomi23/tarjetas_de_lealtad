# Tarjetas de lealtad digitales (Aurum)

Producto interno Ámbar Rojo. Tarjeta de sellos digital con QR para negocios de
visita recurrente (barberías, clínicas, etc.). **Multi-tenant**: varios negocios
en un solo deploy, cada uno con su slug, branding y recompensas.

## Cómo funciona

1. **Cliente** entra a `/join.html?b=<slug>`, se registra con su WhatsApp →
   obtiene su tarjeta con un **QR único** en la misma página (instalable como
   PWA). También puede guardarla en Apple/Google Wallet si están configurados.
2. **Personal** escanea el QR del cliente con la **app Flutter** (escáner
   nativo) → suma un sello. Cooldown de 120s contra doble escaneo.
3. Al alcanzar cada meta de sellos (`reward_tiers`, puede haber varias) suma un
   premio; al completar la meta máxima la tarjeta se reinicia.
4. El premio se entrega con el botón **Canjear** del panel (web o app), que
   descuenta el pendiente (`POST /api/redeem`).
5. **Dueño** entra a `/admin.html?b=<slug>` → KPIs, gráfica de 14 días, clientes
   con búsqueda/orden, canje de premios, exportar CSV, recompensas y branding.
6. **Ámbar Rojo** administra los negocios desde `/superadmin.html`
   (`SUPER_PASS`): alta, edición y métricas de todos los tenants.

El cliente nunca se autosella: sellar y canjear requieren clave. El dueño puede
definir una **clave de personal** separada (en Configuración) que solo sirve
para sellar/canjear, sin acceso al panel.

## Correr

```bash
npm install
SUPER_PASS=algo-seguro npm start
```

Abre `http://localhost:3000`. Producción: PM2 + nginx + certbot (ver `DEPLOY.md`).

## Configuración (variables de entorno)

| Variable        | Default       | Para qué |
|-----------------|---------------|----------|
| `SUPER_PASS`    | super-cambiar | Clave del superadmin (Ámbar Rojo) |
| `PORT`          | 3000          | Puerto |
| `DB_FILE`       | loyalty.db    | Archivo SQLite |
| `WEBHOOK_URL`   | —             | URL de n8n para avisar cuando un cliente gana premio (opcional) |
| `DEFAULT_SLUG`, `BUSINESS_NAME`, `ADMIN_PASS`, … | — | Semilla del primer negocio (solo primer arranque) |
| `APPLE_*` / `GOOGLE_*` | — | Certs/keys de wallets (opcionales; sin ellas los botones se ocultan) |

La configuración por negocio (nombre, colores, logo, tagline, ciclo, clave,
recompensas) vive en la base de datos y se edita desde los paneles.

## Archivos

- `db.js` — lógica + SQLite (negocios, clientes, sellos, canje). Probado en `test.js`.
- `server.js` — API HTTP (Express): auth scrypt, rate-limit, endpoints.
- `wallet.js` — Apple Wallet (.pkpass) y Google Wallet (JWT).
- `public/` — `join` (cliente/PWA), `admin`, `superadmin`, `landing`, `privacidad`.
- `flutter_app/` — app móvil (cliente + escáner del personal + panel).
  `apiBase` se puede sobreescribir: `flutter run --dart-define=API_BASE=http://10.0.2.2:3000`.

## Pendiente (cuando haga falta, no antes)

- Rate-limit en memoria → `express-rate-limit`/Redis si hay varios procesos.
- Caché offline en `sw.js` (hoy solo habilita la instalación PWA).
