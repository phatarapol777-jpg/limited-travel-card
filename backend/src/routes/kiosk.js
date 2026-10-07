const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const { awardCheckin } = require('../services/checkinService');
const K = require('../services/kioskService');

const router = express.Router();
const SESSION_TTL_SECONDS = 300;
const KIOSK_ONLINE_SECONDS = 20;
const MAX_PHOTO_CHARS = 1_500_000;

function kioskAuth(req, res, next) {
  const kiosk = db.prepare('SELECT * FROM checkin_kiosks WHERE kiosk_code = ?').get(req.params.code);
  const sent = req.headers['x-kiosk-key'];
  if (!kiosk || typeof sent !== 'string' || !K.safeEqual(sent, K.kioskKey(kiosk.kiosk_code))) {
    return res.status(401).json({ error: 'รหัสหรือคีย์ของตู้ไม่ถูกต้อง' });
  }
  req.kiosk = kiosk;
  next();
}

function expireStale() {
  db.prepare("UPDATE checkin_sessions SET status = 'expired' WHERE status = 'open' AND expires_at < ?").run(new Date().toISOString());
}

function activeSession(kioskId) {
  expireStale();
  return db.prepare("SELECT * FROM checkin_sessions WHERE kiosk_id = ? AND status = 'open' ORDER BY created_at DESC LIMIT 1").get(kioskId);
}

function ownedSession(req, res) {
  expireStale();
  const session = db.prepare('SELECT * FROM checkin_sessions WHERE session_id = ?').get(req.params.id);
  if (!session || session.user_id !== req.user.user_id) {
    res.status(404).json({ error: 'ไม่พบเซสชัน (อาจหมดอายุ)' });
    return null;
  }
  return session;
}

// ---- kiosk -> server -------------------------------------------------------

// The kiosk polls this every ~1.5s: it reports its liveness, current BLE token and position, and receives the
// session opened by a traveler (with that traveler's stored face vector) when there is one.
router.post('/:code/heartbeat', kioskAuth, (req, res) => {
  const { ble_token, lat, lng } = req.body || {};
  const now = new Date().toISOString();
  const kiosk = req.kiosk;
  db.prepare('UPDATE checkin_kiosks SET last_seen_at = ?, last_ip = ?, last_lat = ?, last_lng = ? WHERE kiosk_id = ?')
    .run(now, req.ip, Number.isFinite(lat) ? lat : null, Number.isFinite(lng) ? lng : null, kiosk.kiosk_id);

  if (typeof ble_token === 'string' && /^\d{4,12}$/.test(ble_token)) {
    const latest = db.prepare('SELECT token FROM kiosk_ble_tokens WHERE kiosk_id = ? ORDER BY issued_at DESC LIMIT 1').get(kiosk.kiosk_id);
    if (!latest || latest.token !== ble_token) {
      db.prepare('INSERT INTO kiosk_ble_tokens (kiosk_id, token, issued_at) VALUES (?, ?, ?)').run(kiosk.kiosk_id, ble_token, now);
      db.prepare(`DELETE FROM kiosk_ble_tokens WHERE kiosk_id = ? AND issued_at NOT IN
        (SELECT issued_at FROM kiosk_ble_tokens WHERE kiosk_id = ? ORDER BY issued_at DESC LIMIT 20)`).run(kiosk.kiosk_id, kiosk.kiosk_id);
    }
  }

  const location = db.prepare('SELECT location_id, name, province FROM locations WHERE location_id = ?').get(kiosk.location_id);
  const session = activeSession(kiosk.kiosk_id);
  let payload = null;
  if (session) {
    const user = db.prepare('SELECT first_name, last_name, face_descriptor FROM users WHERE user_id = ?').get(session.user_id);
    payload = {
      session_id: session.session_id,
      user_id: session.user_id,
      user_name: user ? `${user.first_name} ${user.last_name}` : null,
      session_key: session.session_key,
      stored_face_vector: user && user.face_descriptor ? JSON.parse(user.face_descriptor) : null,
      environment_ok: session.env_ok === null ? null : !!session.env_ok,
      expires_at: session.expires_at,
    };
  }
  res.json({ kiosk: { kiosk_code: kiosk.kiosk_code, location }, session: payload });
});

// Final report from the kiosk. The kiosk has already decided locally (for the door / screen); the server repeats every
// check from the raw evidence before awarding anything, so a stolen kiosk key cannot fake a "passed" result.
router.post('/:code/session/:id/result', kioskAuth, (req, res) => {
  expireStale();
  const session = db.prepare('SELECT * FROM checkin_sessions WHERE session_id = ? AND kiosk_id = ?').get(req.params.id, req.kiosk.kiosk_id);
  if (!session) return res.status(404).json({ error: 'ไม่พบเซสชัน' });
  if (session.status !== 'open') return res.status(409).json({ error: 'เซสชันนี้ปิดไปแล้ว', status: session.status });

  const { live_descriptor, qr_payload, photo_base64, edge_passed, edge_ms } = req.body || {};
  const reasons = [];
  const checks = { hmac: false, time: false, ble: false, face: false, environment: false };
  let score = null;

  const qr = K.checkQr(qr_payload, session);
  checks.hmac = qr.hmac && qr.user;
  checks.time = qr.time;
  if (!checks.hmac) reasons.push('QR ไม่ถูกต้องหรือไม่ใช่ของผู้ใช้นี้ (HMAC)');
  if (!checks.time) reasons.push('QR หมดเวลา (เกิน 3 นาที)');

  if (qr.bleToken) {
    const cutoff = new Date(Date.now() - K.BLE_TOKEN_MAX_AGE_S * 1000).toISOString();
    checks.ble = !!db.prepare('SELECT 1 FROM kiosk_ble_tokens WHERE kiosk_id = ? AND token = ? AND issued_at >= ?')
      .get(req.kiosk.kiosk_id, qr.bleToken, cutoff);
  }
  if (!checks.ble) reasons.push('รหัส BLE ไม่ตรงกับที่ตู้ปล่อย');

  const user = db.prepare('SELECT face_descriptor FROM users WHERE user_id = ?').get(session.user_id);
  if (!user || !user.face_descriptor) {
    reasons.push('ผู้ใช้ยังไม่ได้ลงทะเบียนใบหน้า');
  } else if (!K.validDescriptor(live_descriptor)) {
    reasons.push('ไม่มีข้อมูลใบหน้าสดที่ถูกต้อง');
  } else {
    const distance = K.faceDistance(JSON.parse(user.face_descriptor), live_descriptor);
    score = Math.round(K.similarityScore(distance) * 10) / 10;
    checks.face = distance <= K.FACE_MATCH_THRESHOLD;
    if (!checks.face) reasons.push(`ใบหน้าไม่ตรง (ความเหมือน ${score}% ต่ำกว่า ${K.FACE_PASS_SCORE}%)`);
  }

  checks.environment = !K.ENV_CHECK_ENABLED || session.env_ok === 1;
  if (!checks.environment) reasons.push('ตรวจสภาพแวดล้อมไม่ผ่าน (มือถือไม่ได้อยู่ใกล้ตู้)');

  const verified = Object.values(checks).every(Boolean);
  const photo = typeof photo_base64 === 'string' && /^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(photo_base64) && photo_base64.length <= MAX_PHOTO_CHARS
    ? photo_base64 : null;
  const now = new Date().toISOString();

  let result = null;
  if (verified) result = awardCheckin(session.user_id, session.location_id);
  db.prepare('UPDATE checkin_sessions SET status = ?, face_photo = ?, result_json = ? WHERE session_id = ?')
    .run(verified ? 'completed' : 'rejected', photo, JSON.stringify(verified ? result : { reasons }), session.session_id);
  db.prepare(`INSERT INTO checkin_audit (log_id, session_id, user_id, kiosk_id, created_at, face_match_score, passed, edge_passed, edge_ms, reason, checks_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(newId('log'), session.session_id, session.user_id, req.kiosk.kiosk_id, now, score, verified ? 1 : 0,
      edge_passed === true ? 1 : edge_passed === false ? 0 : null, Number.isFinite(edge_ms) ? Math.round(edge_ms) : null,
      verified ? null : reasons.join('; '), JSON.stringify(checks));

  res.json({ verified, score, checks, reasons, ...(verified ? { result } : {}) });
});

// ---- traveler (phone) -> server ---------------------------------------------

// Step 1: the traveler scanned the kiosk's static QR. Opens the check-in session for this user.
router.post('/open', authMiddleware, (req, res) => {
  expireStale();
  const { kiosk_code } = req.body || {};
  const kiosk = typeof kiosk_code === 'string' ? db.prepare('SELECT * FROM checkin_kiosks WHERE kiosk_code = ?').get(kiosk_code) : null;
  if (!kiosk) return res.status(404).json({ error: 'ไม่พบตู้เช็คอินนี้' });
  if (!req.user.face_descriptor) {
    return res.status(409).json({ code: 'no_face_enrolled', error: 'ยังไม่ได้ลงทะเบียนใบหน้า กรุณาสแกนใบหน้าที่หน้าโปรไฟล์ก่อนเช็คอิน' });
  }
  if (!kiosk.last_seen_at || Date.now() - new Date(kiosk.last_seen_at).getTime() > KIOSK_ONLINE_SECONDS * 1000) {
    return res.status(409).json({ error: 'ตู้นี้ยังไม่ออนไลน์ กรุณาตรวจสอบเครื่องที่ตู้' });
  }
  const busy = db.prepare("SELECT user_id FROM checkin_sessions WHERE kiosk_id = ? AND status = 'open'").get(kiosk.kiosk_id);
  if (busy && busy.user_id !== req.user.user_id) {
    return res.status(409).json({ error: 'ตู้กำลังใช้งาน กรุณารอสักครู่' });
  }
  db.prepare("UPDATE checkin_sessions SET status = 'expired' WHERE kiosk_id = ? AND status = 'open'").run(kiosk.kiosk_id);

  const now = new Date();
  const sessionId = newId('ksn');
  const sessionKey = crypto.randomBytes(16).toString('hex');
  db.prepare(`INSERT INTO checkin_sessions (session_id, kiosk_id, location_id, user_id, status, session_key, result_json, created_at, expires_at)
    VALUES (?, ?, ?, ?, 'open', ?, NULL, ?, ?)`)
    .run(sessionId, kiosk.kiosk_id, kiosk.location_id, req.user.user_id, sessionKey, now.toISOString(),
      new Date(now.getTime() + SESSION_TTL_SECONDS * 1000).toISOString());
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(kiosk.location_id);
  res.status(201).json({ session_id: sessionId, session_key: sessionKey, user_id: req.user.user_id, expires_in: SESSION_TTL_SECONDS, kiosk_code: kiosk.kiosk_code, location });
});

// The phone's copy of the kiosk's "BLE broadcast". Real BLE needs a native app; the browser build relays it here.
router.get('/session/:id/ble', authMiddleware, (req, res) => {
  const session = ownedSession(req, res);
  if (!session) return;
  const row = db.prepare('SELECT token, issued_at FROM kiosk_ble_tokens WHERE kiosk_id = ? ORDER BY issued_at DESC LIMIT 1').get(session.kiosk_id);
  if (!row) return res.status(404).json({ error: 'ยังไม่ได้รับสัญญาณจากตู้' });
  res.json({ token: row.token });
});

// Silent telemetry: what the phone can observe about its surroundings. Browsers cannot read Wi-Fi/BLE lists, so the
// environment check uses the shared network (public IP) and GPS distance to the kiosk instead.
router.post('/session/:id/telemetry', authMiddleware, (req, res) => {
  const session = ownedSession(req, res);
  if (!session) return;
  if (session.status !== 'open') return res.status(409).json({ error: 'เซสชันนี้ปิดไปแล้ว' });
  const kiosk = db.prepare('SELECT * FROM checkin_kiosks WHERE kiosk_id = ?').get(session.kiosk_id);
  const location = db.prepare('SELECT latitude, longitude FROM locations WHERE location_id = ?').get(session.location_id);
  const { lat, lng } = req.body || {};
  const hasGps = Number.isFinite(lat) && Number.isFinite(lng);

  const ipMatch = K.sameNetwork(req.ip, kiosk.last_ip);
  const kioskLat = kiosk.last_lat ?? location.latitude;
  const kioskLng = kiosk.last_lng ?? location.longitude;
  const distance = hasGps ? Math.round(K.haversineMeters(lat, lng, kioskLat, kioskLng)) : null;
  const geoMatch = distance !== null && distance <= K.GEO_RADIUS_M;
  const ok = !K.ENV_CHECK_ENABLED || ipMatch || geoMatch;

  db.prepare('UPDATE checkin_sessions SET env_ok = ?, phone_ip = ?, phone_lat = ?, phone_lng = ? WHERE session_id = ?')
    .run(ok ? 1 : 0, req.ip, hasGps ? lat : null, hasGps ? lng : null, session.session_id);
  res.json({ environment_ok: ok, same_network: ipMatch, distance_m: distance, radius_m: K.GEO_RADIUS_M });
});

router.get('/session/:id', authMiddleware, (req, res) => {
  const session = ownedSession(req, res);
  if (!session) return;
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(session.location_id);
  res.json({
    session_id: session.session_id,
    status: session.status,
    location,
    result: session.result_json ? JSON.parse(session.result_json) : null,
  });
});

module.exports = router;
