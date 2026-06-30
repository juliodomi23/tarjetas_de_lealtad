const express = require('express');
const path = require('path');
const {
  openDb, listBusinesses, getBusinessBySlug, createBusiness, updateBusiness,
  join, addStamp, getRewardTiers, addRewardTier, updateRewardTier, deleteRewardTier,
  stats, listCustomers,
} = require('./db');

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
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── Middlewares ───────────────────────────────────────────────────────────────

function superAdmin(req, res, next) {
  const pass = (req.headers.authorization || '').replace('Bearer ', '');
  if (pass !== SUPER_PASS) return res.status(401).json({ error: 'No autorizado' });
  next();
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
  const pass = (req.headers.authorization || '').replace('Bearer ', '');
  if (pass !== req.biz.admin_pass) return res.status(401).json({ error: 'No autorizado' });
  next();
}

// ── Negocios (público y super-admin) ─────────────────────────────────────────

// Lista pública: solo campos que el cliente necesita para mostrar el picker
app.get('/api/businesses', (req, res) =>
  res.json(listBusinesses(db).map(b => ({
    id: b.id, slug: b.slug, name: b.name,
    primary_color: b.primary_color, logo_url: b.logo_url,
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
  const updated = updateBusiness(db, req.params.slug, req.body);
  res.json(updated);
});

// Vista enriquecida para el panel de Ámbar Rojo (incluye métricas y admin_pass)
app.get('/api/admin/businesses', superAdmin, (req, res) => {
  const list = listBusinesses(db);
  const enriched = list.map(b => ({
    ...b,
    customers: db.prepare('SELECT COUNT(*) n FROM customers WHERE business_id=?').get(b.id).n,
    total_stamps: db.prepare('SELECT COUNT(*) n FROM stamps_log WHERE business_id=?').get(b.id).n,
    new_today: db.prepare(`SELECT COUNT(*) n FROM customers WHERE business_id=? AND date(created_at)=date('now','localtime')`).get(b.id).n,
    admin_pass: db.prepare('SELECT admin_pass FROM businesses WHERE id=?').get(b.id).admin_pass,
  }));
  res.json(enriched);
});

// ── Config por negocio (público) ──────────────────────────────────────────────

app.get('/api/config', withBusiness, (req, res) => {
  const b = req.biz;
  res.json({
    id: b.id, slug: b.slug, business: b.name,
    primary_color: b.primary_color, logo_url: b.logo_url,
    cycle_days: b.cycle_days,
    reward_tiers: getRewardTiers(db, b.id),
  });
});

// ── Clientes ──────────────────────────────────────────────────────────────────

app.post('/api/join', (req, res) => {
  const biz = getBusinessBySlug(db, req.body.business_slug);
  if (!biz) return res.status(404).json({ error: 'Negocio no encontrado' });
  try {
    const token = join(db, biz.id, req.body.phone, req.body.name);
    res.json({ token, business: { id: biz.id, slug: biz.slug, name: biz.name, primary_color: biz.primary_color, logo_url: biz.logo_url } });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.get('/api/card', (req, res) => {
  const c = db.prepare(`SELECT c.*, b.name AS business_name, b.slug, b.primary_color, b.logo_url, b.cycle_days, b.id AS business_id
    FROM customers c JOIN businesses b ON c.business_id=b.id WHERE c.token=?`).get(req.query.t);
  if (!c) return res.status(404).json({ error: 'No encontrado' });
  res.json({
    name: c.name, stamps: c.stamps, total_rewards: c.total_rewards, cycle_start: c.cycle_start,
    business: c.business_name, slug: c.slug, primary_color: c.primary_color,
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
  const pass = (req.headers.authorization || '').replace('Bearer ', '');
  if (pass !== biz.admin_pass) return res.status(401).json({ error: 'Clave incorrecta' });
  try { res.json(addStamp(db, token, biz)); }
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
  const biz = updateBusiness(db, req.biz.slug, {
    name:          req.body.name,
    primary_color: req.body.primary_color,
    logo_url:      req.body.logo_url,
    cycle_days:    req.body.cycle_days !== undefined ? Number(req.body.cycle_days) : undefined,
  });
  res.json(biz);
});

app.listen(PORT, () => console.log(`Lealtad multi-tenant en http://localhost:${PORT}`));
