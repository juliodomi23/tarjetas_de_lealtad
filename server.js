const express = require('express');
const path = require('path');
const { openDb, join, addStamp, getRewardTiers, addRewardTier, updateRewardTier, deleteRewardTier, stats, listCustomers, getSetting, setSetting } = require('./db');

const PORT = process.env.PORT || 3000;
const BUSINESS = process.env.BUSINESS_NAME || 'Mi Negocio';
const ADMIN_PASS = process.env.ADMIN_PASS || 'cambiar';
const PRIMARY_COLOR = process.env.PRIMARY_COLOR || '#E23B3B';
const LOGO_URL = process.env.LOGO_URL || '';
const CYCLE_DAYS = Number(process.env.CYCLE_DAYS || 30);

const db = openDb(process.env.DB_FILE || 'loyalty.db');
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function cfg(key, envFallback) {
  return getSetting(db, key, envFallback);
}

app.get('/api/config', (req, res) =>
  res.json({
    business:      cfg('business', BUSINESS),
    primary_color: cfg('primary_color', PRIMARY_COLOR),
    logo_url:      cfg('logo_url', LOGO_URL),
    cycle_days:    Number(cfg('cycle_days', CYCLE_DAYS)),
    reward_tiers:  getRewardTiers(db),
  }));

app.post('/api/join', (req, res) => {
  try {
    res.json({ token: join(db, req.body.phone, req.body.name) });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.get('/api/card', (req, res) => {
  const c = db.prepare('SELECT name, stamps, total_rewards, cycle_start FROM customers WHERE token=?').get(req.query.t);
  if (!c) return res.status(404).json({ error: 'No encontrado' });
  res.json({ ...c, business: cfg('business', BUSINESS), reward_tiers: getRewardTiers(db), cycle_days: Number(cfg('cycle_days', CYCLE_DAYS)) });
});

function staff(req, res, next) {
  const pass = (req.headers.authorization || '').replace('Bearer ', '');
  if (pass !== ADMIN_PASS) return res.status(401).json({ error: 'No autorizado' });
  next();
}

app.post('/api/stamp', staff, (req, res) => {
  try { res.json(addStamp(db, req.body.token, Number(cfg('cycle_days', CYCLE_DAYS)))); }
  catch (e) { res.status(400).json({ error: e.message }); }
});

// Configuración del negocio (lectura y escritura)
app.get('/api/settings', staff, (req, res) => {
  res.json({
    business:      cfg('business', BUSINESS),
    primary_color: cfg('primary_color', PRIMARY_COLOR),
    logo_url:      cfg('logo_url', LOGO_URL),
    cycle_days:    Number(cfg('cycle_days', CYCLE_DAYS)),
  });
});

app.put('/api/settings', staff, (req, res) => {
  const allowed = ['business', 'primary_color', 'logo_url', 'cycle_days'];
  for (const key of allowed) {
    if (req.body[key] !== undefined) setSetting(db, key, String(req.body[key]));
  }
  res.json({
    business:      cfg('business', BUSINESS),
    primary_color: cfg('primary_color', PRIMARY_COLOR),
    logo_url:      cfg('logo_url', LOGO_URL),
    cycle_days:    Number(cfg('cycle_days', CYCLE_DAYS)),
  });
});

// CRUD recompensas (solo personal/dueño)
app.get('/api/reward-tiers', staff, (req, res) => res.json(getRewardTiers(db)));

app.post('/api/reward-tiers', staff, (req, res) => {
  const { stamps_required, description } = req.body;
  if (!stamps_required || !description) return res.status(400).json({ error: 'Faltan campos' });
  res.json(addRewardTier(db, Number(stamps_required), description));
});

app.put('/api/reward-tiers/:id', staff, (req, res) => {
  const { stamps_required, description } = req.body;
  res.json(updateRewardTier(db, req.params.id, Number(stamps_required), description));
});

app.delete('/api/reward-tiers/:id', staff, (req, res) =>
  res.json(deleteRewardTier(db, req.params.id)));

app.get('/api/stats', staff, (req, res) =>
  res.json({ ...stats(db), business: BUSINESS }));

app.get('/api/customers', staff, (req, res) => res.json(listCustomers(db)));

app.listen(PORT, () => console.log(`Tarjetas de lealtad "${BUSINESS}" en http://localhost:${PORT}`));
