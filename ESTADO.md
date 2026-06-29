# Estado del proyecto — Tarjetas de lealtad

Documento de traspaso. Quien continúe: lee esto y el `README.md`.

**Última actualización:** 2026-06-28

---

## Qué está listo y funcionando

- **Backend** (`server.js` + `db.js`, Express + SQLite): registro, sellos, premios.
  Probado en `test.js` (`node test.js` → OK).
- **Web del cliente/personal** (`public/`): `join`, `card` (QR), `scan` (cámara).
- **App Flutter** (`flutter_app/`): mismas pantallas en móvil + escáner del personal.
  `flutter analyze` limpio. Falta solo configurar `apiBase` y `brand` por negocio.
- **Panel del dueño** (`public/admin.html`): KPIs, gráfica de 14 días, tabla de
  clientes con buscador/orden y enlace a WhatsApp. Responsive (PC y cel).
  Endpoints `GET /api/stats` y `GET /api/customers` (protegidos con `ADMIN_PASS`).

**Modelo actual:** una instancia (un proceso + una DB) por negocio, configurada
con variables de entorno. Ver tabla en `README.md`.

---

## Siguiente tarea grande: MULTITENANT

Objetivo: varios negocios en **un solo deploy** en vez de una instancia por
cliente (hoy cada negocio = un proceso + una `.db` + sus env vars).

### Decisiones a tomar antes de codear
1. **Aislamiento de datos:** ¿una DB por tenant, o una sola DB con columna
   `tenant_id` en cada tabla? (Recomendado para empezar: **DB por tenant** —
   más simple de aislar y respaldar; el código casi no cambia, solo elegir el
   archivo `.db` según el tenant.)
2. **Cómo se identifica el tenant en cada request:** subdominio
   (`tijerazo.lealtad.app`) vs ruta (`/t/tijerazo/...`). Subdominio es más limpio
   para el cliente pero pide wildcard DNS + SSL.
3. **Config por tenant** (hoy son env vars globales): `business`, `goal`,
   `reward_text`, `admin_pass`, color de marca, logo → mover a una tabla
   `tenants` o un JSON por negocio.
4. **Alta de tenants:** ¿panel de super-admin (Ámbar Rojo) o alta manual por
   config? Empezar manual, panel después.

### Por dónde NO empezar
No reescribas todo. El `db.js` ya recibe `db` como parámetro en todas las
funciones → casi todo el trabajo es: resolver qué `db`/config usar según el
tenant del request y pasarlo. La lógica de negocio no cambia.

---

## Backlog recomendado (prioridad sugerida)

| # | Qué | Por qué | Esfuerzo |
|---|-----|---------|----------|
| 1 | **Anti-doble-sello en servidor** | Hoy `addStamp` no tiene cooldown; si el personal escanea el mismo QR 2 veces seguidas, suma 2 sellos (el lock es solo en el cliente). Añadir cooldown por token (ej. ignorar < 30s desde el último sello). | Bajo |
| 2 | **Clave separada dueño vs personal** | Hoy comparten `ADMIN_PASS`. El dueño no debería dar la misma clave a sus empleados. | Bajo |
| 3 | **Aviso por WhatsApp al ganar premio** | Ya guardamos el teléfono. Enganchar `/api/stamp` (cuando `earned: true`) a un workflow n8n. Encaja con el stack de Ámbar Rojo. | Medio |
| 4 | **Registro de canje de premio** | Hoy `rewards` solo sube; no hay forma de marcar un premio como canjeado. El dueño necesita saber cuántos están pendientes de entregar. | Medio |
| 5 | **Exportar clientes a CSV** | Para que el dueño use los datos en su propio marketing. Un endpoint + botón. | Bajo |
| 6 | **Rate limiting en `/api/join`** | Evitar registros basura/spam. | Bajo |
| 7 | **Respaldo de la SQLite** | Un cron que copie el `.db`. Crítico antes de tener clientes reales. | Bajo |

---

## Notas técnicas para quien continúe

- **Cámara del escáner en celular requiere HTTPS** (dominio con SSL o túnel). En
  `localhost` funciona sin SSL.
- **Prefijo de teléfono:** el panel arma el enlace de WhatsApp con `52` (México)
  hardcodeado en `admin.html` (`wa = p => '52' + p`). Revisar al internacionalizar.
- **Normalización de teléfono** (`db.js`, `normPhone`): solo quita no-dígitos.
  Para `+52`/`521` puede hacer falta calibrar si aparecen duplicados.
- Para probar el panel con datos: levanta el server con un `DB_FILE` de prueba,
  registra clientes vía `/api/join` y sella vía `/api/stamp`.
