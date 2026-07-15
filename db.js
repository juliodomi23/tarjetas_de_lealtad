const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

// SQLite datetime('now') devuelve 'YYYY-MM-DD HH:MM:SS' sin zona — tratar como UTC.
function parseDbDate(s) {
  return new Date(s.includes('T') ? s : s.replace(' ', 'T') + 'Z');
}

// ── Claves (scrypt) ───────────────────────────────────────────────────────────

function hashPass(plain) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(String(plain), salt, 32).toString('hex');
  return `scrypt:${salt}:${hash}`;
}

function verifyPass(plain, stored) {
  if (!stored || !stored.startsWith('scrypt:')) return false;
  const [, salt, hash] = stored.split(':');
  const candidate = crypto.scryptSync(String(plain), salt, 32);
  return crypto.timingSafeEqual(candidate, Buffer.from(hash, 'hex'));
}

function openDb(file = 'loyalty.db', seedBusiness = null) {
  const dir = path.dirname(path.resolve(file));
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const db = new Database(file);
  db.pragma('foreign_keys = ON');

  db.exec(`CREATE TABLE IF NOT EXISTS businesses (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    slug          TEXT UNIQUE NOT NULL,
    name          TEXT NOT NULL,
    primary_color TEXT NOT NULL DEFAULT '#E23B3B',
    logo_url      TEXT NOT NULL DEFAULT '',
    card_bg       TEXT NOT NULL DEFAULT '',
    card_bg_image TEXT NOT NULL DEFAULT '',
    card_text_color TEXT NOT NULL DEFAULT '',
    tagline       TEXT NOT NULL DEFAULT '',
    cycle_days    INTEGER NOT NULL DEFAULT 30,
    admin_pass    TEXT NOT NULL,
    staff_pass    TEXT NOT NULL DEFAULT '',
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
  )`);

  db.exec(`CREATE TABLE IF NOT EXISTS customers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    business_id   INTEGER NOT NULL DEFAULT 1,
    token         TEXT UNIQUE NOT NULL,
    phone         TEXT NOT NULL,
    name          TEXT,
    stamps        INTEGER NOT NULL DEFAULT 0,
    total_rewards INTEGER NOT NULL DEFAULT 0,
    redeemed_rewards INTEGER NOT NULL DEFAULT 0,
    cycle_start   TEXT NOT NULL DEFAULT (datetime('now')),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
  )`);

  db.exec(`CREATE TABLE IF NOT EXISTS reward_tiers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    business_id     INTEGER NOT NULL DEFAULT 1,
    stamps_required INTEGER NOT NULL,
    description     TEXT NOT NULL
  )`);

  db.exec(`CREATE TABLE IF NOT EXISTS stamps_log (
    id          INTEGER PRIMARY KEY,
    token       TEXT NOT NULL,
    business_id INTEGER NOT NULL DEFAULT 1,
    ts          TEXT NOT NULL DEFAULT (datetime('now'))
  )`);

  // Migraciones para despliegues anteriores (columnas nuevas)
  try { db.exec(`ALTER TABLE customers ADD COLUMN business_id INTEGER NOT NULL DEFAULT 1`); } catch {}
  try { db.exec(`ALTER TABLE customers ADD COLUMN total_rewards INTEGER NOT NULL DEFAULT 0`); } catch {}
  try { db.exec(`ALTER TABLE customers ADD COLUMN cycle_start TEXT NOT NULL DEFAULT (datetime('now'))`); } catch {}
  try { db.exec(`ALTER TABLE customers ADD COLUMN redeemed_rewards INTEGER NOT NULL DEFAULT 0`); } catch {}
  try { db.exec(`ALTER TABLE reward_tiers ADD COLUMN business_id INTEGER NOT NULL DEFAULT 1`); } catch {}
  try { db.exec(`ALTER TABLE stamps_log ADD COLUMN business_id INTEGER NOT NULL DEFAULT 1`); } catch {}
  try { db.exec(`ALTER TABLE businesses ADD COLUMN card_bg TEXT NOT NULL DEFAULT ''`); } catch {}
  try { db.exec(`ALTER TABLE businesses ADD COLUMN card_bg_image TEXT NOT NULL DEFAULT ''`); } catch {}
  try { db.exec(`ALTER TABLE businesses ADD COLUMN card_text_color TEXT NOT NULL DEFAULT ''`); } catch {}
  try { db.exec(`ALTER TABLE businesses ADD COLUMN tagline TEXT NOT NULL DEFAULT ''`); } catch {}
  try { db.exec(`ALTER TABLE businesses ADD COLUMN staff_pass TEXT NOT NULL DEFAULT ''`); } catch {}

  // Migrar claves en texto plano a scrypt (despliegues anteriores)
  db.prepare(`SELECT id, admin_pass FROM businesses WHERE admin_pass NOT LIKE 'scrypt:%'`).all()
    .forEach(b => db.prepare('UPDATE businesses SET admin_pass=? WHERE id=?').run(hashPass(b.admin_pass), b.id));

  // Sembrar negocio por defecto si no existe ninguno
  if (seedBusiness) {
    db.prepare(`INSERT OR IGNORE INTO businesses (slug,name,primary_color,logo_url,cycle_days,admin_pass)
      VALUES (?,?,?,?,?,?)`)
      .run(seedBusiness.slug, seedBusiness.name, seedBusiness.primary_color,
           seedBusiness.logo_url, seedBusiness.cycle_days, hashPass(seedBusiness.admin_pass));
  }

  return db;
}

// ── Negocios ─────────────────────────────────────────────────────────────────

function listBusinesses(db) {
  return db.prepare('SELECT id,slug,name,primary_color,logo_url,card_bg,card_bg_image,card_text_color,tagline,cycle_days FROM businesses ORDER BY id').all();
}

function getBusinessBySlug(db, slug) {
  return db.prepare('SELECT * FROM businesses WHERE slug=?').get(slug);
}

// Colores hex inválidos guardados aquí crashean el parseo en la app Flutter — validar en la fuente.
const COLOR_FIELDS = ['primary_color', 'card_bg', 'card_text_color'];
function checkColors(fields) {
  for (const k of COLOR_FIELDS) {
    const v = fields[k];
    if (v !== undefined && v !== '' && !/^#[0-9a-fA-F]{6}$/.test(v))
      throw new Error(`Color inválido en ${k} — usa formato #RRGGBB`);
  }
}

function createBusiness(db, { slug, name, primary_color = '#E23B3B', logo_url = '', cycle_days = 30, admin_pass }) {
  checkColors({ primary_color });
  db.prepare(`INSERT INTO businesses (slug,name,primary_color,logo_url,cycle_days,admin_pass)
    VALUES (?,?,?,?,?,?)`)
    .run(slug, name, primary_color, logo_url, cycle_days, hashPass(admin_pass));
  return getBusinessBySlug(db, slug);
}

function updateBusiness(db, slug, fields) {
  checkColors(fields);
  const allowed = ['name', 'primary_color', 'logo_url', 'card_bg', 'card_bg_image', 'card_text_color', 'tagline', 'cycle_days', 'admin_pass', 'staff_pass'];
  // staff_pass vacío = desactivada (el personal usa la del dueño); solo se hashea si trae valor
  const sets = allowed.filter(k => fields[k] !== undefined).map(k => `${k}=?`).join(',');
  const vals = allowed.filter(k => fields[k] !== undefined)
    .map(k => k === 'admin_pass' || (k === 'staff_pass' && fields[k] !== '') ? hashPass(fields[k]) : fields[k]);
  if (!sets) return getBusinessBySlug(db, slug);
  db.prepare(`UPDATE businesses SET ${sets} WHERE slug=?`).run(...vals, slug);
  return getBusinessBySlug(db, slug);
}

// ── Clientes ─────────────────────────────────────────────────────────────────

const normPhone = p => String(p).replace(/\D/g, '');

function join(db, businessId, phone, name) {
  phone = normPhone(phone);
  if (phone.length < 10) throw new Error('Teléfono inválido');
  const existing = db.prepare('SELECT token FROM customers WHERE business_id=? AND phone=?').get(businessId, phone);
  if (existing) return existing.token;
  const token = crypto.randomBytes(8).toString('hex');
  db.prepare('INSERT INTO customers (business_id,token,phone,name) VALUES (?,?,?,?)').run(businessId, token, phone, name || '');
  return token;
}

// ── Recompensas ───────────────────────────────────────────────────────────────

function getRewardTiers(db, businessId) {
  return db.prepare('SELECT * FROM reward_tiers WHERE business_id=? ORDER BY stamps_required').all(businessId);
}

function addRewardTier(db, businessId, stamps_required, description) {
  db.prepare('INSERT INTO reward_tiers (business_id,stamps_required,description) VALUES (?,?,?)').run(businessId, stamps_required, description);
  return getRewardTiers(db, businessId);
}

function updateRewardTier(db, businessId, id, stamps_required, description) {
  db.prepare('UPDATE reward_tiers SET stamps_required=?,description=? WHERE id=? AND business_id=?').run(stamps_required, description, id, businessId);
  return getRewardTiers(db, businessId);
}

function deleteRewardTier(db, businessId, id) {
  db.prepare('DELETE FROM reward_tiers WHERE id=? AND business_id=?').run(id, businessId);
  return getRewardTiers(db, businessId);
}

// ── Sellos ────────────────────────────────────────────────────────────────────

function addStamp(db, token, business, cooldownSecs = 120) {
  const c = db.prepare('SELECT * FROM customers WHERE token=?').get(token);
  if (!c) throw new Error('Cliente no encontrado');
  if (c.business_id !== business.id) throw new Error('Tarjeta no válida para este negocio');

  // Evita doble escaneo accidental (o sellos regalados en ráfaga)
  if (cooldownSecs > 0) {
    const recent = db.prepare(`SELECT 1 FROM stamps_log WHERE token=? AND ts > datetime('now', ?) LIMIT 1`)
      .get(token, `-${cooldownSecs} seconds`);
    if (recent) throw new Error('Esta tarjeta ya fue sellada hace un momento');
  }

  const tiers = getRewardTiers(db, business.id);
  const maxStamps = tiers.length > 0 ? Math.max(...tiers.map(t => t.stamps_required)) : 0;

  let currentStamps = c.stamps;
  let cycleStart = c.cycle_start || c.created_at;
  if (business.cycle_days > 0) {
    const daysElapsed = (Date.now() - parseDbDate(cycleStart).getTime()) / 86400000;
    if (daysElapsed >= business.cycle_days) {
      currentStamps = 0;
      cycleStart = new Date().toISOString();
    }
  }

  const prevStamps = currentStamps;
  const newStamps = currentStamps + 1;
  const earned = tiers.filter(t => prevStamps < t.stamps_required && newStamps >= t.stamps_required);
  const totalRewards = (c.total_rewards || 0) + earned.length;

  let finalStamps = newStamps;
  let reset = false;
  if (maxStamps > 0 && newStamps >= maxStamps) {
    finalStamps = 0;
    cycleStart = new Date().toISOString();
    reset = true;
  }

  db.prepare('UPDATE customers SET stamps=?,total_rewards=?,cycle_start=? WHERE token=?')
    .run(finalStamps, totalRewards, cycleStart, token);
  db.prepare('INSERT INTO stamps_log (token,business_id) VALUES (?,?)').run(token, business.id);

  return { stamps: finalStamps, total_rewards: totalRewards, earned, reset, max_stamps: maxStamps };
}

// ── Canje ─────────────────────────────────────────────────────────────────────

// Marca un premio ganado como entregado. pending = total_rewards - redeemed_rewards.
function redeemReward(db, token, business) {
  const c = db.prepare('SELECT * FROM customers WHERE token=?').get(token);
  if (!c) throw new Error('Cliente no encontrado');
  if (c.business_id !== business.id) throw new Error('Tarjeta no válida para este negocio');
  const pending = (c.total_rewards || 0) - (c.redeemed_rewards || 0);
  if (pending <= 0) throw new Error('Sin premios pendientes por canjear');
  db.prepare('UPDATE customers SET redeemed_rewards=redeemed_rewards+1 WHERE token=?').run(token);
  return { total_rewards: c.total_rewards, redeemed_rewards: c.redeemed_rewards + 1, pending: pending - 1 };
}

// ── Métricas ──────────────────────────────────────────────────────────────────

function stats(db, businessId) {
  const c = db.prepare(`SELECT
    COUNT(*)                       AS customers,
    COALESCE(SUM(stamps),0)        AS in_progress,
    COALESCE(SUM(total_rewards),0) AS rewards,
    SUM(CASE WHEN date(created_at)=date('now','localtime') THEN 1 ELSE 0 END) AS new_today
    FROM customers WHERE business_id=?`).get(businessId);
  const visits = db.prepare('SELECT COUNT(*) n FROM stamps_log WHERE business_id=?').get(businessId).n;
  const daily = db.prepare(`SELECT date(ts) d, COUNT(*) n FROM stamps_log
    WHERE business_id=? AND ts>=datetime('now','-14 days')
    GROUP BY date(ts) ORDER BY d`).all(businessId);
  return { customers: c.customers, visits, rewards: c.rewards, in_progress: c.in_progress, new_today: c.new_today, daily };
}

function listCustomers(db, businessId) {
  return db.prepare(`SELECT token,name,phone,stamps,total_rewards AS rewards,
    total_rewards - redeemed_rewards AS pending_rewards,created_at,cycle_start
    FROM customers WHERE business_id=? ORDER BY created_at DESC`).all(businessId);
}

module.exports = {
  openDb, parseDbDate, hashPass, verifyPass,
  listBusinesses, getBusinessBySlug, createBusiness, updateBusiness,
  normPhone, join,
  getRewardTiers, addRewardTier, updateRewardTier, deleteRewardTier,
  addStamp, redeemReward, stats, listCustomers,
};
