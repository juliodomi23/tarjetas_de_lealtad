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
      foregroundColor:    business.card_text_color ? `rgb(${hexToRgb(business.card_text_color)})` : autoTextColor(business.primary_color),
      labelColor:         business.card_text_color ? `rgb(${hexToRgb(business.card_text_color)})` : autoTextColor(business.primary_color),
      // Sin esto Apple nunca vuelve a pedir el pase: es una foto congelada del
      // momento en que se agrego a Wallet. Con webServiceURL, el telefono se
      // registra y nosotros avisamos por push cuando cambian los sellos.
      // Apple agrega "/v1/devices/..." automaticamente a este valor — NO
      // llevar el /v1 aqui tambien, o Apple llama a una ruta con /v1/v1/
      // duplicado que no existe (404 silencioso, sin log, nunca se registra
      // ningun dispositivo). Confirmado con la spec real de PassKit Web Service.
      webServiceURL:       `${APP_URL}/apple-wallet`,
      authenticationToken: customer.token,
    },
  );

  // Nombre chico arriba (como "NAME" en el header) y los sellos grandes al centro
  // — así se ve una tarjeta de lealtad real, no una ficha con el nombre gigante.
  pass.headerFields.push({ key: 'name', label: 'CLIENTE', value: customer.name || 'Cliente' });

  const pendingRewards = customer.pending_rewards || 0;
  if (pendingRewards > 0) {
    // Al ganar, los sellos se reinician a 0 para el siguiente ciclo — sin esto
    // la tarjeta no dice nada y el cliente puede olvidar que ya tiene un premio
    // esperando. Esto manda arriba y grande, antes que el progreso normal.
    pass.primaryFields.push({
      key: 'reward',
      label: pendingRewards > 1 ? `${pendingRewards} PREMIOS LISTOS` : 'PREMIO LISTO',
      value: '🎁 Pídelo en el mostrador',
    });
    pass.secondaryFields.push({
      key: 'stamps',
      label: nextTier ? nextTier.description.toUpperCase() : 'SELLOS',
      value: `${customer.stamps} / ${maxStamps}`,
    });
  } else {
    pass.primaryFields.push({
      key: 'stamps',
      label: nextTier ? nextTier.description.toUpperCase() : 'SELLOS',
      value: `${customer.stamps} / ${maxStamps} ★`,
    });
  }
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

// Compartido entre el link de "guardar" y la actualizacion en vivo: si hay
// premio pendiente, el area grande (loyaltyPoints) avisa eso en vez del
// numero de sellos — sin esto, al ganar y reiniciarse a 0 el cliente puede
// olvidar que ya tiene un premio esperando.
function loyaltyPointsFields(customer, nextTier) {
  const pendingRewards = customer.pending_rewards || 0;
  if (pendingRewards > 0) {
    return {
      // El PATCH de Google fusiona balance en vez de reemplazarlo — sin poner
      // int:null explicito, se queda el int viejo Y el string nuevo a la vez,
      // y Google lo rechaza (400 "More than one type of loyalty point balances").
      loyaltyPoints: {
        label: pendingRewards > 1 ? `${pendingRewards} premios listos` : '🎁 Premio listo',
        balance: { int: null, string: 'Pídelo en el mostrador' },
      },
      ...(nextTier ? {
        secondaryLoyaltyPoints: {
          label: 'Sellos',
          balance: { string: `${customer.stamps} / ${nextTier.stamps_required}` },
        },
      } : {}),
    };
  }
  return {
    // string:null limpia el balance de texto que pudo quedar de un estado
    // anterior de "premio listo" (mismo choque que arriba, en reversa).
    loyaltyPoints: { label: 'Sellos', balance: { string: null, int: customer.stamps } },
    // Antes solo decia "Cafe gratis: 3/5" — dejaba que el cliente hiciera la
    // resta el solo. Ahora dice cuantos faltan de una vez.
    ...(nextTier ? {
      secondaryLoyaltyPoints: {
        label:   `Faltan ${nextTier.stamps_required - customer.stamps} para: ${nextTier.description}`,
        balance: { string: `${customer.stamps} / ${nextTier.stamps_required}` },
      },
    } : {}),
  };
}

function googleConfigured() {
  return !!(jwt && process.env.GOOGLE_SERVICE_ACCOUNT && process.env.GOOGLE_ISSUER_ID);
}

// Por defecto Google Wallet no pinta accountName en la vista frontal de la
// tarjeta (solo en el detalle expandido) — este override le dice que si lo
// muestre, en su propia fila.
const CARD_TEMPLATE_OVERRIDE = {
  cardRowTemplateInfos: [
    { oneItem: { item: { firstValue: { fields: [{ fieldPath: 'object.accountName' }] } } } },
  ],
};

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
    classTemplateInfo: { cardTemplateOverride: CARD_TEMPLATE_OVERRIDE },
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
    // Sin accountId: Google Wallet lo usa como texto de respaldo cerca del
    // codigo de barras sin ninguna etiqueta — se veia como un numero suelto
    // random (el telefono del cliente). No lo usamos para nada, se quita.
    accountName: customer.name || 'Cliente',
    // Sin alternateText: si no, Google Wallet muestra el token interno del
    // cliente como texto crudo debajo del QR (feo y no le sirve de nada).
    barcode: { type: 'QR_CODE', value: customer.token },
    textModulesData: [{ id: 'cliente', header: 'CLIENTE', body: customer.name || 'Cliente' }],
    ...loyaltyPointsFields(customer, nextTier),
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
        classTemplateInfo: { cardTemplateOverride: CARD_TEMPLATE_OVERRIDE },
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
      // PATCH solo toca los campos que se mandan — objetos creados antes de un
      // fix (accountId, alternateText del barcode, textModulesData) se quedaban
      // viejos para siempre aunque el resto del codigo ya estuviera corregido.
      // Cada sello/canje ahora resincroniza todo el objeto, no solo los sellos,
      // asi que cualquier tarjeta vieja se autocorrige la proxima vez que se use.
      body: JSON.stringify({
        accountName: customer.name || 'Cliente',
        accountId: null,
        barcode: { type: 'QR_CODE', value: customer.token, alternateText: null },
        textModulesData: [{ id: 'cliente', header: 'CLIENTE', body: customer.name || 'Cliente' }],
        ...loyaltyPointsFields(customer, nextTier),
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
      // Sin esto APNs puede demorar la entrega arbitrariamente (la prioridad
      // por defecto no es inmediata) — para el "wake up y revisa tu pase" de
      // Wallet, Apple pide mandarla con prioridad alta.
      'apns-priority': '10',
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

// Negro o blanco segun que tan claro sea el fondo (luminancia relativa) — asi
// un negocio puede poner fondo blanco, negro o cualquier color sin que el
// texto quede invisible. Solo se usa como respaldo: si el dueno ya eligio
// un color de texto en su panel, ese manda.
function autoTextColor(hex) {
  const n = parseInt((hex || '').replace('#', ''), 16);
  if (isNaN(n)) return 'rgb(255,255,255)';
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.6 ? 'rgb(20,20,20)' : 'rgb(255,255,255)';
}

module.exports = {
  generateApplePass, googleWalletSaveUrl, appleConfigured, googleConfigured,
  sendApplePush, updateGoogleLoyaltyObject, updateGoogleLoyaltyClass,
};
