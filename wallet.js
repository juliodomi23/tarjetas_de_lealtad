'use strict';
const path = require('path');
const http2 = require('http2');

const APP_URL = process.env.APP_URL || 'https://lealtad.ambarrojostudios.cloud';

// ── Apple Wallet ──────────────────────────────────────────────────────────────

let PKPass;
try { ({ PKPass } = require('passkit-generator')); } catch (_) {}

function appleConfigured() {
  return !!(PKPass &&
    process.env.APPLE_TEAM_ID &&
    process.env.APPLE_PASS_TYPE_ID &&
    process.env.APPLE_WWDR &&
    process.env.APPLE_CERT &&
    process.env.APPLE_KEY);
}

// Logo/foto del negocio son URLs configuradas por el dueño; se descargan al vuelo
// y se meten al .pkpass como logo.png/strip.png. Si fallan (URL caída, timeout),
// el pase se genera igual sin esa imagen — nunca debe tronar por esto.
async function fetchImageBuffer(url) {
  if (!url) return null;
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!r.ok) return null;
    return Buffer.from(await r.arrayBuffer());
  } catch { return null; }
}

async function generateApplePass(customer, business, tiers) {
  if (!appleConfigured()) throw new Error('Apple Wallet no configurado');

  const maxStamps = tiers.length ? Math.max(...tiers.map(t => t.stamps_required)) : 10;
  const nextTier  = tiers.find(t => t.stamps_required > customer.stamps);
  const left      = nextTier ? nextTier.stamps_required - customer.stamps : 0;

  const pass = await PKPass.from(
    {
      model: path.join(__dirname, 'pass-models/stamp.pass'),
      certificates: {
        wwdr:       Buffer.from(process.env.APPLE_WWDR, 'base64'),
        signerCert: Buffer.from(process.env.APPLE_CERT, 'base64'),
        signerKey:  Buffer.from(process.env.APPLE_KEY,  'base64'),
        // passkit-generator rechaza signerKeyPassphrase vacio; solo se manda si la llave tiene contrasena.
        ...(process.env.APPLE_KEY_PASS ? { signerKeyPassphrase: process.env.APPLE_KEY_PASS } : {}),
      },
    },
    {
      passTypeIdentifier: process.env.APPLE_PASS_TYPE_ID,
      teamIdentifier:     process.env.APPLE_TEAM_ID,
      serialNumber:       customer.token,
      organizationName:   business.name,
      description:        `Lealtad ${business.name}`,
      backgroundColor:    `rgb(${hexToRgb(business.primary_color || '#8B1A1A')})`,
      foregroundColor:    'rgb(255,255,255)',
      labelColor:         'rgb(201,168,76)',
      // Sin esto Apple nunca vuelve a pedir el pase: es una foto congelada del
      // momento en que se agrego a Wallet. Con webServiceURL, el telefono se
      // registra y nosotros avisamos por push cuando cambian los sellos.
      webServiceURL:       `${APP_URL}/apple-wallet/v1`,
      authenticationToken: customer.token,
    },
  );

  // Nombre chico arriba (como "NAME" en el header) y los sellos grandes al centro
  // — así se ve una tarjeta de lealtad real, no una ficha con el nombre gigante.
  pass.headerFields.push({ key: 'name', label: 'CLIENTE', value: customer.name || 'Cliente' });
  pass.primaryFields.push({
    key: 'stamps',
    label: nextTier ? nextTier.description.toUpperCase() : 'SELLOS',
    value: `${customer.stamps} / ${maxStamps} ★`,
  });
  if (nextTier) {
    pass.auxiliaryFields.push({ key: 'left', label: 'FALTAN', value: `${left} sellos` });
  }
  pass.backFields.push(
    { key: 'howto',   label: '¿Cómo usar?', value: 'Muestra el código QR en el mostrador. El staff lo escanea y acumulas un sello.' },
    { key: 'negocio', label: 'Negocio',     value: business.name },
  );
  pass.setBarcodes({ message: customer.token, format: 'PKBarcodeFormatQR', messageEncoding: 'iso-8859-1' });

  const [logoBuf, stripBuf] = await Promise.all([
    fetchImageBuffer(business.logo_url),
    fetchImageBuffer(business.card_bg_image),
  ]);
  if (logoBuf) pass.addBuffer('logo.png', logoBuf);
  if (stripBuf) pass.addBuffer('strip.png', stripBuf);

  return pass.getAsBuffer();
}

// ── Google Wallet ─────────────────────────────────────────────────────────────

let jwt;
try { jwt = require('jsonwebtoken'); } catch (_) {}

function googleConfigured() {
  return !!(jwt && process.env.GOOGLE_SERVICE_ACCOUNT && process.env.GOOGLE_ISSUER_ID);
}

function googleWalletSaveUrl(customer, business, tiers) {
  if (!googleConfigured()) throw new Error('Google Wallet no configurado');

  const creds     = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT);
  const issuerId  = process.env.GOOGLE_ISSUER_ID;
  const classId   = `${issuerId}.${business.slug}`;
  const objectId  = `${issuerId}.${customer.token}`;
  const maxStamps = tiers.length ? Math.max(...tiers.map(t => t.stamps_required)) : 10;
  const nextTier  = tiers.find(t => t.stamps_required > customer.stamps);

  const loyaltyClass = {
    id:                classId,
    issuerName:        business.name,
    programName:       `Lealtad ${business.name}`,
    hexBackgroundColor: business.primary_color || '#8B1A1A',
    reviewStatus:      'UNDER_REVIEW',
    // Google Wallet rechaza la clase si no trae programLogo; usamos el logo de Aurum si el negocio no tiene el suyo.
    programLogo: {
      sourceUri: { uri: business.logo_url || 'https://lealtad.ambarrojostudios.cloud/Logo.jpg' },
      contentDescription: { defaultValue: { language: 'es', value: business.name } },
    },
    // Foto de fondo del negocio (misma que usa la tarjeta en la app); sin ella
    // Google Wallet se ve bien igual, solo sin la banda de imagen arriba.
    ...(business.card_bg_image ? {
      heroImage: {
        sourceUri: { uri: business.card_bg_image },
        contentDescription: { defaultValue: { language: 'es', value: business.name } },
      },
    } : {}),
  };

  const loyaltyObject = {
    id:          objectId,
    classId,
    state:       'ACTIVE',
    accountId:   customer.phone,
    accountName: customer.name || 'Cliente',
    loyaltyPoints: { label: 'Sellos', balance: { int: customer.stamps } },
    // Sin alternateText: si no, Google Wallet muestra el token interno del
    // cliente como texto crudo debajo del QR (feo y no le sirve de nada).
    barcode: { type: 'QR_CODE', value: customer.token },
    textModulesData: [{ id: 'cliente', header: 'CLIENTE', body: customer.name || 'Cliente' }],
    ...(nextTier ? {
      secondaryLoyaltyPoints: {
        label:   nextTier.description,
        balance: { string: `${customer.stamps} / ${nextTier.stamps_required}` },
      },
    } : {}),
  };

  const token = jwt.sign(
    {
      iss:     creds.client_email,
      aud:     'google',
      typ:     'savetowallet',
      iat:     Math.floor(Date.now() / 1000),
      payload: { loyaltyClasses: [loyaltyClass], loyaltyObjects: [loyaltyObject] },
    },
    creds.private_key,
    { algorithm: 'RS256' },
  );

  return `https://pay.google.com/gp/v/save/${token}`;
}

// Token OAuth2 para hablar con la Wallet REST API (a diferencia del JWT
// "savetowallet", que solo sirve para el link de guardar del lado del cliente).
async function googleAccessToken(creds) {
  const now = Math.floor(Date.now() / 1000);
  const authJwt = jwt.sign(
    { iss: creds.client_email, scope: 'https://www.googleapis.com/auth/wallet_object.issuer',
      aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 },
    creds.private_key, { algorithm: 'RS256' },
  );
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: authJwt }),
  });
  return (await r.json()).access_token;
}

// El link "savetowallet" solo CREA la clase la primera vez; una vez que Google
// la aprueba, ese mismo link ya no la vuelve a actualizar (para que una marca
// no cambie su branding sin pasar de nuevo por revision) — asi que cambiar el
// logo o la foto en el panel no se veia reflejado aunque el codigo los mandara
// bien. Hay que empujarlos con un PATCH explicito a la clase por su cuenta.
async function updateGoogleLoyaltyClass(business) {
  if (!googleConfigured()) return;
  try {
    const creds   = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT);
    const classId = `${process.env.GOOGLE_ISSUER_ID}.${business.slug}`;
    const access_token = await googleAccessToken(creds);
    if (!access_token) return;

    const r = await fetch(`https://walletobjects.googleapis.com/walletobjects/v1/loyaltyClass/${classId}`, {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        issuerName: business.name,
        programName: `Lealtad ${business.name}`,
        hexBackgroundColor: business.primary_color || '#8B1A1A',
        // Google exige reenviar a revision cualquier cambio de marca a una
        // clase ya aprobada (rechaza el PATCH si no se manda esto) — mientras
        // la revisen, el cliente sigue viendo el diseno anterior, no se rompe nada.
        reviewStatus: 'UNDER_REVIEW',
        programLogo: {
          sourceUri: { uri: business.logo_url || 'https://lealtad.ambarrojostudios.cloud/Logo.jpg' },
          contentDescription: { defaultValue: { language: 'es', value: business.name } },
        },
        ...(business.card_bg_image ? {
          heroImage: {
            sourceUri: { uri: business.card_bg_image },
            contentDescription: { defaultValue: { language: 'es', value: business.name } },
          },
        } : {}),
      }),
    });
    if (!r.ok) console.error('actualizar loyaltyClass de Google fallo:', r.status, await r.text());
  } catch (e) { console.error('actualizar loyaltyClass de Google fallo:', e.message); }
}

// El link "savetowallet" solo crea/actualiza el objeto la primera vez que el
// cliente le da "Guardar". Sellar despues no vuelve a llamar ese link, asi que
// sin esto la tarjeta se queda pegada con el numero de sellos de cuando se
// guardo. Google Wallet SI se actualiza solo en el telefono una vez que el
// objeto cambia aqui (a diferencia de Apple, no hace falta avisarle nada mas).
async function updateGoogleLoyaltyObject(customer, business, tiers) {
  if (!googleConfigured()) return;
  try {
    const creds    = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT);
    const objectId = `${process.env.GOOGLE_ISSUER_ID}.${customer.token}`;
    const nextTier = tiers.find(t => t.stamps_required > customer.stamps);
    const access_token = await googleAccessToken(creds);
    if (!access_token) return;

    const r = await fetch(`https://walletobjects.googleapis.com/walletobjects/v1/loyaltyObject/${objectId}`, {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        loyaltyPoints: { label: 'Sellos', balance: { int: customer.stamps } },
        ...(nextTier ? {
          secondaryLoyaltyPoints: {
            label:   nextTier.description,
            balance: { string: `${customer.stamps} / ${nextTier.stamps_required}` },
          },
        } : {}),
      }),
    });
    if (!r.ok) console.error('actualizar loyaltyObject de Google fallo:', r.status, await r.text());
  } catch (e) { console.error('actualizar loyaltyObject de Google fallo:', e.message); }
}

// Avisa al iPhone (via APNs) que revise de nuevo el pase — dispara la llamada
// del telefono a GET /apple-wallet/v1/passes/... El mismo certificado que firma
// el pase sirve para autenticar el push (es un Pass Type ID cert, no necesita
// llave .p8 aparte). Silencioso si falla: un push perdido no debe tronar nada.
function sendApplePush(pushToken) {
  return new Promise(resolve => {
    if (!appleConfigured()) return resolve();
    let client;
    try {
      client = http2.connect('https://api.push.apple.com', {
        cert: Buffer.from(process.env.APPLE_CERT, 'base64'),
        key:  Buffer.from(process.env.APPLE_KEY,  'base64'),
        passphrase: process.env.APPLE_KEY_PASS || undefined,
      });
    } catch { return resolve(); }
    client.on('error', () => resolve());
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${pushToken}`,
      'apns-topic': process.env.APPLE_PASS_TYPE_ID,
    });
    req.on('response', () => { client.close(); resolve(); });
    req.on('error', () => { client.close(); resolve(); });
    req.end('{}');
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function hexToRgb(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
}

module.exports = {
  generateApplePass, googleWalletSaveUrl, appleConfigured, googleConfigured,
  sendApplePush, updateGoogleLoyaltyObject, updateGoogleLoyaltyClass,
};
