'use strict';
const path = require('path');

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
    barcode: { type: 'QR_CODE', value: customer.token, alternateText: customer.token },
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

// ── Helpers ───────────────────────────────────────────────────────────────────

function hexToRgb(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
}

module.exports = { generateApplePass, googleWalletSaveUrl, appleConfigured, googleConfigured };
