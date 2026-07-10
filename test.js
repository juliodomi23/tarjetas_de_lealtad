const assert = require('assert');
const { openDb, createBusiness, join, addStamp, addRewardTier, stats, listCustomers, verifyPass } = require('./db');

const db = openDb(':memory:');
const biz = createBusiness(db, { slug: 'test', name: 'Test', admin_pass: 'x', cycle_days: 30 });
addRewardTier(db, biz.id, 3, 'Premio chico');

// claves: se guardan hasheadas y verifican solo con la clave correcta
assert(biz.admin_pass.startsWith('scrypt:'), 'clave hasheada en BD');
assert(verifyPass('x', biz.admin_pass), 'clave correcta verifica');
assert(!verifyPass('mala', biz.admin_pass), 'clave incorrecta no verifica');

// mismo teléfono (con distinto formato) => mismo cliente/token
const t = join(db, biz.id, '55 1234 5678', 'Ana');
assert.strictEqual(t.length, 16);
assert.strictEqual(join(db, biz.id, '5512345678', 'Ana'), t, 'mismo phone => mismo token');
assert.throws(() => join(db, biz.id, '123', 'corto'), /inválido/);

// ciclo de sellos con meta 3: se reinicia y suma premio al completar (cooldown 0 para el test)
let r;
r = addStamp(db, t, biz, 0); assert.deepStrictEqual([r.stamps, r.earned.length], [1, 0]);
r = addStamp(db, t, biz, 0); assert.deepStrictEqual([r.stamps, r.earned.length], [2, 0]);
r = addStamp(db, t, biz, 0); assert.deepStrictEqual([r.stamps, r.earned.length, r.total_rewards, r.reset], [0, 1, 1, true]);
r = addStamp(db, t, biz, 0); assert.strictEqual(r.stamps, 1, 'nuevo ciclo empieza en 1');
assert.throws(() => addStamp(db, 'token-falso', biz), /no encontrado/);

// cooldown: dos sellos seguidos con cooldown activo => rechazado
assert.throws(() => addStamp(db, t, biz), /ya fue sellada/, 'doble escaneo bloqueado');

// stats: 1 cliente, 4 sellos en bitácora, 1 premio, 1 sello en curso
const s = stats(db, biz.id);
assert.strictEqual(s.customers, 1);
assert.strictEqual(s.visits, 4, 'bitácora cuenta todos los sellos');
assert.strictEqual(s.rewards, 1);
assert.strictEqual(s.in_progress, 1);
assert.strictEqual(listCustomers(db, biz.id).length, 1);

// aislamiento multi-tenant: tarjeta de un negocio no sella en otro
const biz2 = createBusiness(db, { slug: 'otro', name: 'Otro', admin_pass: 'y' });
assert.throws(() => addStamp(db, t, biz2), /no válida/);
assert.strictEqual(listCustomers(db, biz2.id).length, 0);

console.log('OK');
