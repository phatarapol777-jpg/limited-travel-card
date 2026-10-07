const crypto = require('crypto');
const db = require('../db');
const { SECRET } = require('../secret');

// ---- kiosk identity -------------------------------------------------------
// Each kiosk has a code (KSK-001) and a key derived from the server secret (see ../secret.js), so keys survive
// database resets as long as KIOSK_SECRET is set in the environment.
const KIOSK_SECRET = SECRET;

function kioskKey(code) {
  // a kiosk without a code would get the same key as every other code-less kiosk: refuse instead
  if (!code) throw new Error('kioskKey needs a kiosk code');
  return crypto.createHmac('sha256', KIOSK_SECRET).update(`kiosk|${code}`).digest('hex').slice(0, 20);
}

/** The next free code: KSK-001, KSK-002, ... one above the highest number in use. */
function nextKioskCode() {
  const max = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(kiosk_code, 5) AS INTEGER)), 0) AS m FROM checkin_kiosks WHERE kiosk_code LIKE 'KSK-%'").get().m;
  return `KSK-${String(max + 1).padStart(3, '0')}`;
}

/** Gives every kiosk that has no code its own (run at boot, and by the admin list as a safety net). */
function ensureKioskCodes() {
  const pending = db.prepare('SELECT kiosk_id FROM checkin_kiosks WHERE kiosk_code IS NULL ORDER BY rowid').all();
  const assign = db.prepare('UPDATE checkin_kiosks SET kiosk_code = ? WHERE kiosk_id = ?');
  db.transaction(() => {
    for (const k of pending) assign.run(nextKioskCode(), k.kiosk_id);
  })();
  return pending.length;
}

// ---- check parameters -----------------------------------------------------
const FACE_MATCH_THRESHOLD = parseFloat(process.env.FACE_MATCH_THRESHOLD) || 0.5; // euclidean distance (face-api)
// Similarity % = 100 - 30 * distance, so the 85% pass mark is exactly distance 0.5 (the threshold tested on real faces).
// It is a linear rescaling for display, not a probability.
const SCORE_SLOPE = 30;
const FACE_PASS_SCORE = 100 - SCORE_SLOPE * FACE_MATCH_THRESHOLD;
const QR_TIME_WINDOW_S = 180;
const BLE_TOKEN_MAX_AGE_S = 180;
const HMAC_LEN = 12;
const GEO_RADIUS_M = parseInt(process.env.KIOSK_GEO_RADIUS_M, 10) || 300;
const ENV_CHECK_ENABLED = String(process.env.ENV_CHECK || 'on').toLowerCase() !== 'off';

function faceDistance(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += (a[i] - b[i]) ** 2;
  return Math.sqrt(sum);
}

function similarityScore(distance) {
  return Math.max(0, Math.min(100, 100 - SCORE_SLOPE * distance));
}

function validDescriptor(d) {
  return Array.isArray(d) && d.length === 128 && d.every((n) => typeof n === 'number' && Number.isFinite(n));
}

function qrHmac(sessionKey, userId, bleToken, ts) {
  return crypto.createHmac('sha256', sessionKey).update(`${userId}|${bleToken}|${ts}`).digest('hex').slice(0, HMAC_LEN);
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** Parses "User_ID|BLE_Token|Timestamp|HMAC" and verifies it against the session. */
function checkQr(payload, session, nowMs = Date.now()) {
  const out = { hmac: false, time: false, user: false, bleToken: null };
  if (typeof payload !== 'string' || payload.length > 200) return out;
  const parts = payload.split('|');
  if (parts.length !== 4) return out;
  const [userId, bleToken, tsStr, mac] = parts;
  const ts = Number(tsStr);
  out.bleToken = bleToken;
  out.user = userId === session.user_id;
  out.hmac = Number.isFinite(ts) && safeEqual(mac, qrHmac(session.session_key, userId, bleToken, tsStr));
  out.time = Number.isFinite(ts) && Math.abs(nowMs / 1000 - ts) <= QR_TIME_WINDOW_S;
  return out;
}

// ---- environment check ----------------------------------------------------
function normalizeIp(ip) {
  return String(ip || '').replace(/^::ffff:/, '');
}

function expandIpv6(ip) {
  const [head, tail = ''] = ip.split('::');
  const h = head ? head.split(':') : [];
  const t = tail ? tail.split(':') : [];
  const missing = 8 - h.length - t.length;
  return [...h, ...Array(ip.includes('::') ? missing : 0).fill('0'), ...t].map((x) => x.padStart(4, '0'));
}

/** Same network if IPv4 addresses match, or IPv6 addresses share a /64. Mixed families are not comparable. */
function sameNetwork(a, b) {
  const x = normalizeIp(a);
  const y = normalizeIp(b);
  if (!x || !y) return false;
  const v6x = x.includes(':');
  const v6y = y.includes(':');
  if (v6x !== v6y) return false;
  if (!v6x) return x === y;
  return expandIpv6(x).slice(0, 4).join(':') === expandIpv6(y).slice(0, 4).join(':');
}

function haversineMeters(lat1, lng1, lat2, lng2) {
  const rad = (d) => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(a));
}

module.exports = {
  kioskKey, ensureKioskCodes, nextKioskCode, faceDistance, similarityScore, validDescriptor, qrHmac, checkQr, safeEqual,
  sameNetwork, haversineMeters, normalizeIp,
  FACE_MATCH_THRESHOLD, FACE_PASS_SCORE, QR_TIME_WINDOW_S, BLE_TOKEN_MAX_AGE_S, GEO_RADIUS_M, ENV_CHECK_ENABLED, HMAC_LEN,
};
