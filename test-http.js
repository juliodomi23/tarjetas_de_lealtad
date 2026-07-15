// Test de integración HTTP: levanta server.js real y ejercita el flujo completo.
// Corre con: node test-http.js (incluido en npm test)
const assert = require('assert');
const cp = require('child_process');
const fs = require('fs');

const PORT = 3997;
const DB = 'test-http-tmp.db';
const BASE = `http://localhost:${PORT}`;

const req = async (method, url, { body, auth } = {}) => {
  const r = await fetch(BASE + url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: `Bearer ${auth}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, data: await r.json().catch(() => ({})) };
};

async function main() {
  // Alta de negocio (superadmin) y recompensa
  let r = await req('POST', '/api/businesses', { body: { slug: 'nuevo', name: 'Nuevo', admin_pass: 'dueno1' }, auth: 'sup' });
  assert.strictEqual(r.status, 200, 'superadmin crea negocio');
  r = await req('POST', '/api/businesses', { body: { slug: 'x', name: 'X', admin_pass: 'x' }, auth: 'clave-mala' });
  assert.strictEqual(r.status, 401, 'superadmin con clave mala → 401');

  await req('POST', '/api/nuevo/reward-tiers', { body: { stamps_required: 2, description: 'Premio' }, auth: 'dueno1' });

  // Clave de personal separada: sella pero no ve el panel
  r = await req('PUT', '/api/nuevo/settings', { body: { staff_pass: 'staff1' }, auth: 'dueno1' });
  assert.strictEqual(r.status, 200, 'dueño define clave de personal');

  // Registro de cliente
  r = await req('POST', '/api/join', { body: { business_slug: 'nuevo', phone: '9930000001', name: 'Ana' } });
  assert.strictEqual(r.status, 200, 'join ok');
  const token = r.data.token;

  // Sello con clave de personal
  r = await req('POST', '/api/stamp', { body: { token }, auth: 'staff1' });
  assert.strictEqual(r.status, 200, 'staff_pass sella');
  // El personal NO entra al panel
  r = await req('GET', '/api/nuevo/stats', { auth: 'staff1' });
  assert.strictEqual(r.status, 401, 'staff_pass no ve el panel');
  r = await req('GET', '/api/nuevo/stats', { auth: 'dueno1' });
  assert.strictEqual(r.status, 200, 'dueño sí ve el panel');

  // Segundo sello: el cooldown de 120s lo bloquea → lo saltamos moviendo el log
  require('better-sqlite3')(DB).prepare(`UPDATE stamps_log SET ts=datetime('now','-5 minutes')`).run();
  r = await req('POST', '/api/stamp', { body: { token }, auth: 'dueno1' });
  assert.strictEqual(r.data.earned.length, 1, 'segundo sello gana premio');

  // Canje con clave de personal; doble canje rechazado
  r = await req('GET', '/api/card?t=' + token);
  assert.strictEqual(r.data.pending_rewards, 1, 'card muestra pendiente');
  r = await req('POST', '/api/redeem', { body: { token }, auth: 'staff1' });
  assert.strictEqual(r.data.pending, 0, 'canje ok con staff_pass');
  r = await req('POST', '/api/redeem', { body: { token }, auth: 'staff1' });
  assert.strictEqual(r.status, 400, 'sin pendientes → 400');

  // Desactivar clave de personal: deja de funcionar, la del dueño sigue
  await req('PUT', '/api/nuevo/settings', { body: { staff_pass: '' }, auth: 'dueno1' });
  r = await req('POST', '/api/stamp', { body: { token: 'token-inexistente' }, auth: 'staff1' });
  assert.strictEqual(r.status, 404, 'valida token antes que clave');
  require('better-sqlite3')(DB).prepare(`UPDATE stamps_log SET ts=datetime('now','-5 minutes')`).run();
  r = await req('POST', '/api/stamp', { body: { token }, auth: 'staff1' });
  assert.strictEqual(r.status, 401, 'staff_pass desactivada → 401');

  // config pública no filtra claves
  r = await req('GET', '/api/config?b=nuevo');
  assert.strictEqual(r.data.admin_pass, undefined, 'config no expone claves');
  assert.strictEqual(r.data.staff_pass, undefined, 'config no expone staff_pass');

  console.log('OK http');
}

// En Windows el unlink del finally puede fallar si el server aún no soltó el
// archivo — limpiamos también antes de arrancar para no heredar datos sucios.
try { fs.unlinkSync(DB); } catch {}

const server = cp.spawn('node', ['server.js'], {
  env: { ...process.env, DB_FILE: DB, PORT: String(PORT), SUPER_PASS: 'sup', ADMIN_PASS: 'seed', DEFAULT_SLUG: 'seed' },
  stdio: ['ignore', 'ignore', 'inherit'],
});

setTimeout(() => {
  main()
    .then(() => process.exitCode = 0)
    .catch(e => { console.error(e.message); process.exitCode = 1; })
    .finally(() => { server.kill(); try { fs.unlinkSync(DB); } catch {} });
}, 1000);
