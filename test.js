const assert = require('assert');
const { openDb, join, addStamp, stats, listCustomers } = require('./db');

const db = openDb(':memory:');

// mismo teléfono (con distinto formato) => mismo cliente/token
const t = join(db, '55 1234 5678', 'Ana');
assert.strictEqual(t.length, 16);
assert.strictEqual(join(db, '5512345678', 'Ana'), t, 'mismo phone => mismo token');
assert.throws(() => join(db, '123', 'corto'), /inválido/);

// ciclo de sellos con meta 3: se reinicia y suma premio al completar
const goal = 3;
let r;
r = addStamp(db, t, goal); assert.deepStrictEqual([r.stamps, r.earned], [1, false]);
r = addStamp(db, t, goal); assert.deepStrictEqual([r.stamps, r.earned], [2, false]);
r = addStamp(db, t, goal); assert.deepStrictEqual([r.stamps, r.earned, r.rewards], [0, true, 1]);
r = addStamp(db, t, goal); assert.strictEqual(r.stamps, 1, 'nuevo ciclo empieza en 1');
assert.throws(() => addStamp(db, 'token-falso', goal), /no encontrado/);

// stats: 1 cliente, 4 sellos en bitácora, 1 premio, 1 sello en curso
const s = stats(db, goal);
assert.strictEqual(s.customers, 1);
assert.strictEqual(s.visits, 4, 'bitácora cuenta todos los sellos');
assert.strictEqual(s.rewards, 1);
assert.strictEqual(s.in_progress, 1);
assert.strictEqual(s.near_reward, 0, 'nadie está a 1 sello (meta 3, tiene 1)');
assert.strictEqual(listCustomers(db).length, 1);

console.log('OK');
