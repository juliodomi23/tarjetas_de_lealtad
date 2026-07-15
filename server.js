const express = require('express');
const path = require('path');
const {
  openDb, listBusinesses, getBusinessBySlug, createBusiness, updateBusiness,
  join, addStamp, redeemReward, getRewardTiers, addRewardTier, updateRewardTier, deleteRewardTier,
  stats, listCustomers, verifyPass,
} = require('./db');
const { generateApplePass, googleWalletSaveUrl, appleConfigured, googleConfigured } = require('./wallet');

const PORT       = process.env.PORT || 3000;
const SUPER_PASS = process.env.SUPER_PASS || 'super-cambiar';
const DEFAULT_SLUG = process.env.DEFAULT_SLUG || 'negocio-1';

const db = openDb(process.env.DB_FILE || 'loyalty.db', {
  slug:          DEFAULT_SLUG,
  name:          process.env.BUSINESS_NAME  || 'Mi Negocio',
  primary_color: process.env.PRIMARY_COLOR  || '#E23B3B',
  logo_url:      process.env.LOGO_URL       || '',
  cycle_days:    Number(process.env.CYCLE_DAYS || 30),
  admin_pass:    process.env.ADMIN_PASS     || 'cambiar',
});

const app = express();
app.set('trust proxy', 1); // nginx delante: usar la IP real del cliente para el rate-limit
app.use(express.json());

// Headers de seguridad básicos (equivalente mínimo a helmet)
app.use((_req, res, next) => {
  res.set({
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    'Strict-Transport-Security': 'max-age=31536000',
  });
  next();
});

app.use(express.static(path.join(__dirname, 'public')));

if (SUPER_PASS === 'super-cambiar')
  console.warn('⚠️  SUPER_PASS sigue en el valor por defecto — cámbialo en ecosystem.config.js / entorno');

// ── Middlewares ───────────────────────────────────────────────────────────────

// ponytail: rate-limit en memoria por IP; pasar a express-rate-limit si hay varios procesos
const failedAuth = new Map(); // ip -> { count, until }
const MAX_FAILS = 10, BLOCK_MS = 15 * 60 * 1000;

function authBlocked(req, res) {
  const rec = failedAuth.get(req.ip);
  if (rec && rec.count >= MAX_FAILS && Date.now() < rec.until) {
    res.status(429).json({ error: 'Demasiados intentos, espera 15 minutos' });
    return true;
  }
  return false;
}

function authFailed(req) {
  const rec = failedAuth.get(req.ip) || { count: 0, until: 0 };
  rec.count++;
  rec.until = Date.now() + BLOCK_MS;
  failedAuth.set(req.ip, rec);
}

function checkPass(req, res, verify) {
  if (authBlocked(req, res)) return false;
  const pass = (req.headers.authorization || '').replace('Bearer ', '');
  const ok = verify(pass);
  if (!ok) { authFailed(req); res.status(401).json({ error: 'No autorizado' }); }
  else failedAuth.delete(req.ip);
  return ok;
}

// SUPER_PASS viene del entorno (no de la BD), se compara en texto plano tiempo-constante
function superPassOk(pass) {
  const crypto = require('crypto');
  return pass.length === SUPER_PASS.length &&
    crypto.timingSafeEqual(Buffer.from(pass), Buffer.from(SUPER_PASS));
}

function superAdmin(req, res, next) {
  if (checkPass(req, res, superPassOk)) next();
}

function withBusiness(req, res, next) {
  const slug = req.params.slug || req.query.b;
  if (!slug) return res.status(400).json({ error: 'Falta el negocio (b=slug)' });
  const biz = getBusinessBySlug(db, slug);
  if (!biz) return res.status(404).json({ error: 'Negocio no encontrado' });
  req.biz = biz;
  next();
}

function staff(req, res, next) {
  if (checkPass(req, res, pass => verifyPass(pass, req.biz.admin_pass))) next();
}

// ── Negocios (público y super-admin) ─────────────────────────────────────────

// Lista pública: solo campos que el cliente necesita para mostrar el picker
app.get('/api/businesses', (req, res) =>
  res.json(listBusinesses(db).map(b => ({
    id: b.id, slug: b.slug, name: b.name,
    primary_color: b.primary_color, logo_url: b.logo_url,
    card_bg: b.card_bg, card_bg_image: b.card_bg_image, card_text_color: b.card_text_color, tagline: b.tagline,
  }))));

app.post('/api/businesses', superAdmin, (req, res) => {
  const { slug, name, primary_color, logo_url, cycle_days, admin_pass } = req.body;
  if (!slug || !name || !admin_pass) return res.status(400).json({ error: 'Faltan campos: slug, name, admin_pass' });
  try {
    const biz = createBusiness(db, { slug, name, primary_color, logo_url, cycle_days, admin_pass });
    res.json(biz);
  } catch (e) { res.status(400).json({ error: e.message }); }
});

// Super-admin puede editar cualquier negocio sin necesitar su admin_pass
app.put('/api/admin/businesses/:slug', superAdmin, (req, res) => {
  const biz = getBusinessBySlug(db, req.params.slug);
  if (!biz) return res.status(404).json({ error: 'Negocio no encontrado' });
  try {
    res.json(updateBusiness(db, req.params.slug, req.body));
  } catch (e) { res.status(400).json({ error: e.message }); }
});

// Vista enriquecida para el panel de Ámbar Rojo (incluye métricas y admin_pass)
app.get('/api/admin/businesses', superAdmin, (req, res) => {
  const list = listBusinesses(db);
  const enriched = list.map(b => ({
    ...b,
    customers: db.prepare('SELECT COUNT(*) n FROM customers WHERE business_id=?').get(b.id).n,
    total_stamps: db.prepare('SELECT COUNT(*) n FROM stamps_log WHERE business_id=?').get(b.id).n,
    new_today: db.prepare(`SELECT COUNT(*) n FROM customers WHERE business_id=? AND date(created_at)=date('now','localtime')`).get(b.id).n,
  }));
  res.json(enriched);
});

// ── Config por negocio (público) ──────────────────────────────────────────────

app.get('/api/config', withBusiness, (req, res) => {
  const b = req.biz;
  res.json({
    id: b.id, slug: b.slug, business: b.name,
    primary_color: b.primary_color, logo_url: b.logo_url,
    card_bg: b.card_bg, card_bg_image: b.card_bg_image, card_text_color: b.card_text_color, tagline: b.tagline,
    cycle_days: b.cycle_days,
    reward_tiers: getRewardTiers(db, b.id),
  });
});

// ── Clientes ──────────────────────────────────────────────────────────────────

// ponytail: rate-limit en memoria por IP; suficiente para un solo proceso
const joinLog = new Map(); // ip -> [timestamps]
const JOIN_MAX = 5, JOIN_WINDOW_MS = 10 * 60 * 1000;

app.post('/api/join', (req, res) => {
  const now = Date.now();
  const hits = (joinLog.get(req.ip) || []).filter(t => now - t < JOIN_WINDOW_MS);
  if (hits.length >= JOIN_MAX)
    return res.status(429).json({ error: 'Demasiados registros, intenta más tarde' });
  hits.push(now);
  joinLog.set(req.ip, hits);

  const biz = getBusinessBySlug(db, req.body.business_slug);
  if (!biz) return res.status(404).json({ error: 'Negocio no encontrado' });
  try {
    const token = join(db, biz.id, req.body.phone, req.body.name);
    res.json({ token, business: { id: biz.id, slug: biz.slug, name: biz.name, primary_color: biz.primary_color, logo_url: biz.logo_url,
      card_bg: biz.card_bg, card_bg_image: biz.card_bg_image, card_text_color: biz.card_text_color, tagline: biz.tagline } });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.get('/api/card', (req, res) => {
  const c = db.prepare(`SELECT c.*, b.name AS business_name, b.slug, b.primary_color, b.logo_url, b.card_bg, b.card_bg_image, b.card_text_color, b.tagline, b.cycle_days, b.id AS business_id
    FROM customers c JOIN businesses b ON c.business_id=b.id WHERE c.token=?`).get(req.query.t);
  if (!c) return res.status(404).json({ error: 'No encontrado' });
  res.json({
    name: c.name, stamps: c.stamps, total_rewards: c.total_rewards,
    pending_rewards: c.total_rewards - (c.redeemed_rewards || 0), cycle_start: c.cycle_start,
    business: c.business_name, slug: c.slug, primary_color: c.primary_color, logo_url: c.logo_url,
    card_bg: c.card_bg, card_bg_image: c.card_bg_image, card_text_color: c.card_text_color, tagline: c.tagline,
    cycle_days: c.cycle_days,
    reward_tiers: getRewardTiers(db, c.business_id),
  });
});

// ── Staff: sellar ─────────────────────────────────────────────────────────────

// El token ya identifica al negocio; verificamos el pass contra ese negocio.
app.post('/api/stamp', (req, res) => {
  const token = req.body.token;
  if (!token) return res.status(400).json({ error: 'Falta token' });
  const customer = db.prepare('SELECT business_id FROM customers WHERE token=?').get(token);
  if (!customer) return res.status(404).json({ error: 'Cliente no encontrado' });
  const biz = db.prepare('SELECT * FROM businesses WHERE id=?').get(customer.business_id);
  if (!checkPass(req, res, pass => verifyPass(pass, biz.admin_pass))) return;
  try { res.json(addStamp(db, token, biz)); }
  catch (e) { res.status(400).json({ error: e.message }); }
});

// Canjear un premio pendiente (misma autenticación que sellar)
app.post('/api/redeem', (req, res) => {
  const token = req.body.token;
  if (!token) return res.status(400).json({ error: 'Falta token' });
  const customer = db.prepare('SELECT business_id FROM customers WHERE token=?').get(token);
  if (!customer) return res.status(404).json({ error: 'Cliente no encontrado' });
  const biz = db.prepare('SELECT * FROM businesses WHERE id=?').get(customer.business_id);
  if (!checkPass(req, res, pass => verifyPass(pass, biz.admin_pass))) return;
  try { res.json(redeemReward(db, token, biz)); }
  catch (e) { res.status(400).json({ error: e.message }); }
});

// ── Staff: panel por negocio ──────────────────────────────────────────────────

app.get('/api/:slug/stats',      withBusiness, staff, (req, res) => res.json(stats(db, req.biz.id)));
app.get('/api/:slug/customers',  withBusiness, staff, (req, res) => res.json(listCustomers(db, req.biz.id)));
app.get('/api/:slug/reward-tiers', withBusiness, staff, (req, res) => res.json(getRewardTiers(db, req.biz.id)));

app.post('/api/:slug/reward-tiers', withBusiness, staff, (req, res) => {
  const stamps_required = Number(req.body.stamps_required);
  const { description } = req.body;
  if (!stamps_required || !description) return res.status(400).json({ error: 'Faltan campos' });
  res.json(addRewardTier(db, req.biz.id, stamps_required, description));
});

app.put('/api/:slug/reward-tiers/:id', withBusiness, staff, (req, res) => {
  const stamps_required = Number(req.body.stamps_required);
  const { description } = req.body;
  if (!stamps_required || !description) return res.status(400).json({ error: 'Faltan campos' });
  res.json(updateRewardTier(db, req.biz.id, req.params.id, stamps_required, description));
});

app.delete('/api/:slug/reward-tiers/:id', withBusiness, staff, (req, res) =>
  res.json(deleteRewardTier(db, req.biz.id, req.params.id)));

app.put('/api/:slug/settings', withBusiness, staff, (req, res) => {
  try {
    const biz = updateBusiness(db, req.biz.slug, {
      name:          req.body.name,
      primary_color: req.body.primary_color,
      logo_url:      req.body.logo_url,
      card_bg:         req.body.card_bg,
      card_bg_image:   req.body.card_bg_image,
      card_text_color: req.body.card_text_color,
      tagline:         req.body.tagline,
      cycle_days:    req.body.cycle_days !== undefined ? Number(req.body.cycle_days) : undefined,
    });
    res.json(biz);
  } catch (e) { res.status(400).json({ error: e.message }); }
});

// ── Wallet ─────────────────────────────────────────────────────────────────────

// Página de registro / tarjeta del cliente
app.get('/join', (_req, res) => res.sendFile(path.join(__dirname, 'public/join.html')));

// Qué wallets están configurados (para la UI)
app.get('/api/wallets', (_req, res) => res.json({ apple: appleConfigured(), google: googleConfigured() }));

// Descarga .pkpass para Apple Wallet
app.get('/api/pass/apple', async (req, res) => {
  const c = db.prepare(`SELECT c.*, b.name AS business_name, b.slug, b.primary_color, b.logo_url, b.id AS business_id
    FROM customers c JOIN businesses b ON c.business_id=b.id WHERE c.token=?`).get(req.query.t);
  if (!c) return res.status(404).json({ error: 'No encontrado' });
  try {
    const buf = await generateApplePass(
      { token: c.token, name: c.name, stamps: c.stamps, phone: c.phone },
      { name: c.business_name, slug: c.slug, primary_color: c.primary_color, logo_url: c.logo_url },
      getRewardTiers(db, c.business_id),
    );
    res.set({ 'Content-Type': 'application/vnd.apple.pkpass', 'Content-Disposition': 'attachment; filename="aurum.pkpass"' });
    res.send(buf);
  } catch (e) { res.status(503).json({ error: e.message }); }
});

// Redirige al link de Google Wallet
app.get('/api/pass/google', (req, res) => {
  const c = db.prepare(`SELECT c.*, b.name AS business_name, b.slug, b.primary_color, b.logo_url, b.id AS business_id
    FROM customers c JOIN businesses b ON c.business_id=b.id WHERE c.token=?`).get(req.query.t);
  if (!c) return res.status(404).json({ error: 'No encontrado' });
  try {
    const url = googleWalletSaveUrl(
      { token: c.token, name: c.name, stamps: c.stamps, phone: c.phone },
      { name: c.business_name, slug: c.slug, primary_color: c.primary_color, logo_url: c.logo_url },
      getRewardTiers(db, c.business_id),
    );
    res.redirect(url);
  } catch (e) { res.status(503).json({ error: e.message }); }
});

app.listen(PORT, () => console.log(`Lealtad multi-tenant en http://localhost:${PORT}`));
