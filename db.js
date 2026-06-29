const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

function openDb(file = 'loyalty.db') {
  const dir = path.dirname(path.resolve(file));
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const db = new Database(file);

  db.exec(`CREATE TABLE IF NOT EXISTS customers (
    token         TEXT PRIMARY KEY,
    phone         TEXT UNIQUE NOT NULL,
    name          TEXT,
    stamps        INTEGER NOT NULL DEFAULT 0,
    total_rewards INTEGER NOT NULL DEFAULT 0,
    cycle_start   TEXT NOT NULL DEFAULT (datetime('now')),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
  )`);

  // Migraciones seguras para DBs existentes
  try { db.exec(`ALTER TABLE customers ADD COLUMN total_rewards INTEGER NOT NULL DEFAULT 0`); } catch {}
  try { db.exec(`ALTER TABLE customers ADD COLUMN cycle_start TEXT NOT NULL DEFAULT (datetime('now'))`); } catch {}

  db.exec(`CREATE TABLE IF NOT EXISTS stamps_log (
    id    INTEGER PRIMARY KEY,
    token TEXT NOT NULL,
    ts    TEXT NOT NULL DEFAULT (datetime('now'))
  )`);

  db.exec(`CREATE TABLE IF NOT EXISTS reward_tiers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    stamps_required INTEGER NOT NULL,
    description     TEXT NOT NULL
  )`);

  db.exec(`CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )`);

  return db;
}

function getSetting(db, key, fallback = '') {
  const row = db.prepare('SELECT value FROM settings WHERE key=?').get(key);
  return row ? row.value : fallback;
}

function setSetting(db, key, value) {
  db.prepare('INSERT INTO settings (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value')
    .run(key, value);
}

const normPhone = p => String(p).replace(/\D/g, '');

function join(db, phone, name) {
  phone = normPhone(phone);
  if (phone.length < 10) throw new Error('Teléfono inválido');
  const existing = db.prepare('SELECT token FROM customers WHERE phone=?').get(phone);
  if (existing) return existing.token;
  const token = crypto.randomBytes(8).toString('hex');
  db.prepare('INSERT INTO customers (token, phone, name) VALUES (?,?,?)').run(token, phone, name || '');
  return token;
}

function getRewardTiers(db) {
  return db.prepare('SELECT * FROM reward_tiers ORDER BY stamps_required').all();
}

function addRewardTier(db, stamps_required, description) {
  db.prepare('INSERT INTO reward_tiers (stamps_required, description) VALUES (?,?)').run(stamps_required, description);
  return getRewardTiers(db);
}

function updateRewardTier(db, id, stamps_required, description) {
  db.prepare('UPDATE reward_tiers SET stamps_required=?, description=? WHERE id=?').run(stamps_required, description, id);
  return getRewardTiers(db);
}

function deleteRewardTier(db, id) {
  db.prepare('DELETE FROM reward_tiers WHERE id=?').run(id);
  return getRewardTiers(db);
}

function addStamp(db, token, cycleDays) {
  const c = db.prepare('SELECT * FROM customers WHERE token=?').get(token);
  if (!c) throw new Error('Cliente no encontrado');

  const tiers = getRewardTiers(db);
  const maxStamps = tiers.length > 0 ? Math.max(...tiers.map(t => t.stamps_required)) : 0;

  // Verificar si el ciclo expiró
  let currentStamps = c.stamps;
  let cycleStart = c.cycle_start || c.created_at;
  if (cycleDays > 0) {
    const msElapsed = Date.now() - new Date(cycleStart).getTime();
    const daysElapsed = msElapsed / (1000 * 60 * 60 * 24);
    if (daysElapsed >= cycleDays) {
      currentStamps = 0;
      cycleStart = new Date().toISOString();
    }
  }

  const prevStamps = currentStamps;
  const newStamps = currentStamps + 1;

  // Recompensas recién cruzadas en este sello
  const earned = tiers.filter(t => prevStamps < t.stamps_required && newStamps >= t.stamps_required);
  const totalRewards = (c.total_rewards || 0) + earned.length;

  // Reinicio al llegar al máximo
  let finalStamps = newStamps;
  let reset = false;
  if (maxStamps > 0 && newStamps >= maxStamps) {
    finalStamps = 0;
    cycleStart = new Date().toISOString();
    reset = true;
  }

  db.prepare('UPDATE customers SET stamps=?, total_rewards=?, cycle_start=? WHERE token=?')
    .run(finalStamps, totalRewards, cycleStart, token);
  db.prepare('INSERT INTO stamps_log (token) VALUES (?)').run(token);

  return { stamps: finalStamps, total_rewards: totalRewards, earned, reset, max_stamps: maxStamps };
}

function stats(db) {
  const c = db.prepare(`SELECT
    COUNT(*)                   AS customers,
    COALESCE(SUM(stamps),0)    AS in_progress,
    COALESCE(SUM(total_rewards),0) AS rewards,
    SUM(CASE WHEN date(created_at) = date('now','localtime') THEN 1 ELSE 0 END) AS new_today
    FROM customers`).get();
  const visits = db.prepare('SELECT COUNT(*) n FROM stamps_log').get().n;
  const daily = db.prepare(`SELECT date(ts) d, COUNT(*) n FROM stamps_log
    WHERE ts >= datetime('now','-14 days') GROUP BY date(ts) ORDER BY d`).all();
  return { customers: c.customers, visits, rewards: c.rewards, in_progress: c.in_progress, new_today: c.new_today, daily };
}

function listCustomers(db) {
  return db.prepare(`SELECT name, phone, stamps, total_rewards AS rewards, created_at, cycle_start
    FROM customers ORDER BY created_at DESC`).all();
}

module.exports = { openDb, join, addStamp, getRewardTiers, addRewardTier, updateRewardTier, deleteRewardTier, normPhone, stats, listCustomers, getSetting, setSetting };
