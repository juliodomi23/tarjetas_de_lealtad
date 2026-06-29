const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

function openDb(file = 'loyalty.db') {
  const dir = path.dirname(path.resolve(file));
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const db = new Database(file);
  db.exec(`CREATE TABLE IF NOT EXISTS customers (
    token      TEXT PRIMARY KEY,
    phone      TEXT UNIQUE NOT NULL,
    name       TEXT,
    stamps     INTEGER NOT NULL DEFAULT 0,
    rewards    INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`);
  // Bitácora de sellos: una fila por sello, para reportes con fecha.
  db.exec(`CREATE TABLE IF NOT EXISTS stamps_log (
    id    INTEGER PRIMARY KEY,
    token TEXT NOT NULL,
    ts    TEXT NOT NULL DEFAULT (datetime('now'))
  )`);
  return db;
}

// ponytail: normalización ingenua (solo dígitos). Para México con lada/+52 puede
// hacer falta calibrar (quitar 521 inicial). Ajustar aquí si hay duplicados.
const normPhone = p => String(p).replace(/\D/g, '');

function join(db, phone, name) {
  phone = normPhone(phone);
  if (phone.length < 10) throw new Error('Teléfono inválido');
  const existing = db.prepare('SELECT token FROM customers WHERE phone=?').get(phone);
  if (existing) return existing.token;
  const token = crypto.randomBytes(8).toString('hex');
  db.prepare('INSERT INTO customers (token, phone, name) VALUES (?,?,?)')
    .run(token, phone, name || '');
  return token;
}

function addStamp(db, token, goal) {
  const c = db.prepare('SELECT * FROM customers WHERE token=?').get(token);
  if (!c) throw new Error('Cliente no encontrado');
  let stamps = c.stamps + 1;
  let earned = false;
  if (stamps >= goal) { stamps = 0; earned = true; } // completa ciclo y reinicia
  const rewards = c.rewards + (earned ? 1 : 0);
  db.prepare('UPDATE customers SET stamps=?, rewards=? WHERE token=?')
    .run(stamps, rewards, token);
  db.prepare('INSERT INTO stamps_log (token) VALUES (?)').run(token);
  return { stamps, rewards, earned, goal };
}

// Métricas para el panel del dueño.
function stats(db, goal) {
  const c = db.prepare(`SELECT
    COUNT(*)                  AS customers,
    COALESCE(SUM(stamps),0)   AS in_progress,
    COALESCE(SUM(rewards),0)  AS rewards,
    SUM(CASE WHEN date(created_at) = date('now','localtime') THEN 1 ELSE 0 END) AS new_today
    FROM customers`).get();
  const near = db.prepare('SELECT COUNT(*) n FROM customers WHERE stamps = ?').get(goal - 1).n;
  const visits = db.prepare('SELECT COUNT(*) n FROM stamps_log').get().n;
  // Sellos por día, últimos 14 días.
  const daily = db.prepare(`SELECT date(ts) d, COUNT(*) n FROM stamps_log
    WHERE ts >= datetime('now','-14 days') GROUP BY date(ts) ORDER BY d`).all();
  return {
    customers: c.customers,
    visits,
    rewards: c.rewards,
    in_progress: c.in_progress,
    near_reward: near,
    new_today: c.new_today,
    daily,
  };
}

function listCustomers(db) {
  return db.prepare(`SELECT name, phone, stamps, rewards, created_at
    FROM customers ORDER BY created_at DESC`).all();
}

module.exports = { openDb, join, addStamp, normPhone, stats, listCustomers };
