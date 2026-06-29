const express = require('express');
const path = require('path');
const { openDb, join, addStamp, stats, listCustomers } = require('./db');

const PORT = process.env.PORT || 3000;
const GOAL = Number(process.env.GOAL || 8);
const BUSINESS = process.env.BUSINESS_NAME || 'Mi Negocio';
const REWARD = process.env.REWARD_TEXT || 'Premio gratis';
const ADMIN_PASS = process.env.ADMIN_PASS || 'cambiar';
const PRIMARY_COLOR = process.env.PRIMARY_COLOR || '#E23B3B';
const LOGO_URL = process.env.LOGO_URL || '';

const db = openDb(process.env.DB_FILE || 'loyalty.db');
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/config', (req, res) =>
  res.json({ business: BUSINESS, goal: GOAL, reward_text: REWARD, primary_color: PRIMARY_COLOR, logo_url: LOGO_URL }));

app.post('/api/join', (req, res) => {
  try {
    res.json({ token: join(db, req.body.phone, req.body.name) });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.get('/api/card', (req, res) => {
  const c = db.prepare('SELECT name, stamps, rewards FROM customers WHERE token=?')
    .get(req.query.t);
  if (!c) return res.status(404).json({ error: 'No encontrado' });
  res.json({ ...c, goal: GOAL, business: BUSINESS, reward_text: REWARD });
});

// Solo el personal del negocio puede sellar (anti-fraude).
function staff(req, res, next) {
  const pass = (req.headers.authorization || '').replace('Bearer ', '');
  if (pass !== ADMIN_PASS) return res.status(401).json({ error: 'No autorizado' });
  next();
}

app.post('/api/stamp', staff, (req, res) => {
  try {
    res.json(addStamp(db, req.body.token, GOAL));
  } catch (e) { res.status(400).json({ error: e.message }); }
});

// Panel del dueño (misma clave que el personal).
app.get('/api/stats', staff, (req, res) =>
  res.json({ ...stats(db, GOAL), goal: GOAL, business: BUSINESS, reward_text: REWARD }));

app.get('/api/customers', staff, (req, res) => res.json(listCustomers(db)));

app.listen(PORT, () =>
  console.log(`Tarjetas de lealtad "${BUSINESS}" en http://localhost:${PORT}`));
