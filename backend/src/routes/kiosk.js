const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const { awardCheckin } = require('../services/checkinService');

const router = express.Router();
const SESSION_TTL_SECONDS = 180;

function getSessionOrRespond404(req, res) {
  const session = db.prepare('SELECT * FROM checkin_sessions WHERE session_id = ?').get(req.params.id);
  if (!session) {
    res.status(404).json({ error: 'ไม่พบเซสชัน (อาจหมดอายุ)' });
    return null;
  }
  if (session.status !== 'completed' && new Date(session.expires_at).getTime() < Date.now()) {
    db.prepare("UPDATE checkin_sessions SET status = 'expired' WHERE session_id = ?").run(session.session_id);
    session.status = 'expired';
  }
  return session;
}

router.post('/session', (req, res) => {
  const { kiosk_id } = req.body || {};
  const kiosk = db.prepare('SELECT * FROM checkin_kiosks WHERE kiosk_id = ?').get(kiosk_id);
  if (!kiosk) return res.status(404).json({ error: 'ไม่พบเครื่องยืนยันตัวตนนี้' });
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(kiosk.location_id);

  const now = new Date();
  const sessionId = newId('ksn');
  const expiresAt = new Date(now.getTime() + SESSION_TTL_SECONDS * 1000).toISOString();
  db.prepare(`INSERT INTO checkin_sessions (session_id, kiosk_id, location_id, user_id, status, result_json, created_at, expires_at)
    VALUES (?, ?, ?, NULL, 'awaiting_scan', NULL, ?, ?)`)
    .run(sessionId, kiosk_id, kiosk.location_id, now.toISOString(), expiresAt);

  res.status(201).json({ session_id: sessionId, qr_payload: `TRVKIOSK|${sessionId}`, expires_in: SESSION_TTL_SECONDS, location });
});

router.get('/session/:id', (req, res) => {
  const session = getSessionOrRespond404(req, res);
  if (!session) return;
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(session.location_id);
  const user = session.user_id ? db.prepare('SELECT first_name, last_name FROM users WHERE user_id = ?').get(session.user_id) : null;
  res.json({
    session_id: session.session_id,
    status: session.status,
    location,
    user,
    result: session.result_json ? JSON.parse(session.result_json) : null,
  });
});

router.post('/session/:id/scan', authMiddleware, (req, res) => {
  const session = getSessionOrRespond404(req, res);
  if (!session) return;
  if (session.status !== 'awaiting_scan') return res.status(400).json({ error: 'เซสชันนี้ถูกใช้ไปแล้วหรือหมดอายุ' });

  db.prepare("UPDATE checkin_sessions SET status = 'awaiting_face', user_id = ? WHERE session_id = ?")
    .run(req.user.user_id, session.session_id);
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(session.location_id);
  res.json({ status: 'awaiting_face', location });
});

router.post('/session/:id/verify-face', (req, res) => {
  const session = getSessionOrRespond404(req, res);
  if (!session) return;
  if (session.status !== 'awaiting_face') return res.status(400).json({ error: 'สถานะเซสชันไม่ถูกต้อง' });

  const { photo_base64 } = req.body || {};
  db.prepare("UPDATE checkin_sessions SET status = 'verified', face_photo = ? WHERE session_id = ?")
    .run(photo_base64 || null, session.session_id);
  res.json({ status: 'verified' });
});

router.post('/session/:id/complete', (req, res) => {
  const session = getSessionOrRespond404(req, res);
  if (!session) return;
  if (session.status !== 'verified') return res.status(400).json({ error: 'สถานะเซสชันไม่ถูกต้อง' });

  const result = awardCheckin(session.user_id, session.location_id);
  db.prepare("UPDATE checkin_sessions SET status = 'completed', result_json = ? WHERE session_id = ?")
    .run(JSON.stringify(result), session.session_id);
  res.json({ status: 'completed', ...result });
});

module.exports = router;
