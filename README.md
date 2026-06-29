# Tarjetas de lealtad digitales

Producto interno Ámbar Rojo. Tarjeta de sellos digital con QR para negocios de
visita recurrente (barberías, clínicas, etc.). **Una instancia por negocio**,
configurada con variables de entorno.

## Cómo funciona

1. **Cliente** entra a `/join.html`, se registra con su WhatsApp → obtiene su
   tarjeta en `/card.html` con un **QR único**.
2. **Personal** abre `/scan.html` (pide una clave una sola vez), escanea el QR
   del cliente con la cámara → suma un sello.
3. Al completar la meta (`GOAL`), la tarjeta se reinicia y suma un premio.
4. **Dueño** entra a `/admin.html` (misma clave del personal) → ve métricas:
   clientes, sellos otorgados, premios, gráfica de actividad de 14 días y lista
   de clientes con enlace directo a WhatsApp.

El cliente nunca se autosella: sellar requiere la clave del personal.

## Correr

```bash
npm install
# copia .env.example a .env y ajusta valores, o exporta las variables
BUSINESS_NAME="Barbería X" GOAL=8 REWARD_TEXT="Corte gratis" ADMIN_PASS=secreto npm start
```

Abre `http://localhost:3000`. Para la cámara del escáner en celular hace falta
**HTTPS** (un dominio con SSL o un túnel tipo Cloudflare/ngrok); en `localhost`
funciona sin SSL.

## Configuración (variables de entorno)

| Variable        | Default       | Para qué |
|-----------------|---------------|----------|
| `BUSINESS_NAME` | Mi Negocio    | Nombre que ve el cliente |
| `GOAL`          | 8             | Sellos para ganar el premio |
| `REWARD_TEXT`   | Premio gratis | Descripción del premio |
| `ADMIN_PASS`    | cambiar       | Clave del personal para sellar |
| `PORT`          | 3000          | Puerto |
| `DB_FILE`       | loyalty.db    | Archivo SQLite |

## Archivos

- `db.js` — lógica + SQLite (registro, sellos). Probado en `test.js`.
- `server.js` — API HTTP (Express).
- `public/` — `join`, `card`, `scan`, `admin` (HTML estático, QR vía CDN).

## Pendiente (cuando haga falta, no antes)

- Multi-negocio en un solo deploy (hoy: 1 instancia = 1 negocio).
- Aviso por WhatsApp al ganar premio (ya guardamos el teléfono → fácil de
  enganchar a n8n con `/api/stamp`).
- Clave separada para dueño vs. personal (hoy comparten `ADMIN_PASS`).
