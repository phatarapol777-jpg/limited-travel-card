const express = require('express');
const crypto = require('crypto');
const db = require('../db');
const { newId, hashPassword, verifyPassword, createSession, authMiddleware, publicUser } = require('../util');

// Only the 128-number face descriptor is stored; the photo itself is never kept (PDPA data minimisation).
function parseFace(body) {
  const { face_descriptor } = body || {};
  if (!Array.isArray(face_descriptor) || face_descriptor.length !== 128 || !face_descriptor.every((n) => typeof n === 'number' && Number.isFinite(n))) {
    return { error: 'ไม่พบใบหน้าในภาพ กรุณาถ่ายใหม่ให้เห็นใบหน้าชัดเจน' };
  }
  return { descriptor: JSON.stringify(face_descriptor) };
}

const router = express.Router();

router.post('/register', (req, res) => {
  const { username, password, first_name, last_name, email, phone } = req.body || {};
  if (!username || !password || !first_name || !last_name || !email) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  const face = parseFace(req.body);
  if (face.error) return res.status(400).json({ error: face.error });
  const existing = db.prepare('SELECT 1 FROM users WHERE username = ? OR email = ?').get(username, email);
  if (existing) return res.status(409).json({ error: 'Username or email already exists' });

  const userId = newId('usr');
  const { hash, salt } = hashPassword(password);
  db.prepare(`INSERT INTO users (user_id, username, password_hash, password_salt, first_name, last_name, email, phone, face_descriptor, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(userId, username, hash, salt, first_name, last_name, email, phone || null, face.descriptor, new Date().toISOString());

  const token = createSession(userId);
  const user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(userId);
  res.status(201).json({ token, user: publicUser(user) });
});

router.post('/login', (req, res) => {
  const { username, password } = req.body || {};
  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!user || !verifyPassword(password || '', user.password_salt, user.password_hash)) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }
  const token = createSession(user.user_id);
  res.json({ token, user: publicUser(user) });
});

async function verifyGoogleIdToken(idToken) {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  if (!clientId) throw Object.assign(new Error('เซิร์ฟเวอร์ยังไม่ได้ตั้งค่า GOOGLE_CLIENT_ID'), { status: 503 });
  const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
  if (!res.ok) throw Object.assign(new Error('Google token ไม่ถูกต้องหรือหมดอายุ'), { status: 401 });
  const info = await res.json();
  if (info.aud !== clientId) throw Object.assign(new Error('Google token ไม่ได้ออกให้แอปนี้'), { status: 401 });
  if (!['accounts.google.com', 'https://accounts.google.com'].includes(info.iss)) throw Object.assign(new Error('ผู้ออก token ไม่ถูกต้อง'), { status: 401 });
  if (!info.sub || !info.email) throw Object.assign(new Error('Google token ไม่มีข้อมูลบัญชี'), { status: 401 });
  return info;
}

function uniqueUsername(base) {
  const clean = (base || 'traveler').toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 20) || 'traveler';
  let candidate = clean;
  while (db.prepare('SELECT 1 FROM users WHERE username = ?').get(candidate)) {
    candidate = `${clean}${Math.floor(1000 + Math.random() * 9000)}`;
  }
  return candidate;
}

router.post('/google', async (req, res) => {
  try {
    const { id_token } = req.body || {};
    if (!id_token || typeof id_token !== 'string') return res.status(400).json({ error: 'Missing id_token' });
    const info = await verifyGoogleIdToken(id_token);
    const emailVerified = info.email_verified === true || info.email_verified === 'true';

    let user = db.prepare('SELECT * FROM users WHERE google_sub = ?').get(info.sub);
    if (!user && emailVerified) {
      const byEmail = db.prepare('SELECT * FROM users WHERE email = ?').get(info.email);
      if (byEmail && !byEmail.is_admin) {
        db.prepare('UPDATE users SET google_sub = ? WHERE user_id = ?').run(info.sub, byEmail.user_id);
        user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(byEmail.user_id);
      }
    }
    if (!user) {
      if (db.prepare('SELECT 1 FROM users WHERE email = ?').get(info.email)) {
        return res.status(409).json({ error: 'อีเมลนี้มีบัญชีอยู่แล้ว กรุณาเข้าสู่ระบบด้วยรหัสผ่าน' });
      }
      const userId = newId('usr');
      const { hash, salt } = hashPassword(crypto.randomBytes(32).toString('hex'));
      db.prepare(`INSERT INTO users (user_id, username, password_hash, password_salt, first_name, last_name, email, phone, face_data, google_sub, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?)`)
        .run(userId, uniqueUsername(info.email.split('@')[0]), hash, salt,
          info.given_name || info.name || 'Google', info.family_name || '-', info.email, info.sub, new Date().toISOString());
      user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(userId);
    }
    res.json({ token: createSession(user.user_id), user: publicUser(user) });
  } catch (err) {
    res.status(err.status || 502).json({ error: err.message || 'Google sign-in failed' });
  }
});

router.put('/face', authMiddleware, (req, res) => {
  const face = parseFace(req.body);
  if (face.error) return res.status(400).json({ error: face.error });
  db.prepare('UPDATE users SET face_photo = NULL, face_descriptor = ? WHERE user_id = ?').run(face.descriptor, req.user.user_id);
  res.json({ has_face: true });
});

router.delete('/face', authMiddleware, (req, res) => {
  db.prepare('UPDATE users SET face_photo = NULL, face_descriptor = NULL WHERE user_id = ?').run(req.user.user_id);
  res.json({ has_face: false });
});

router.get('/me', authMiddleware, (req, res) => {
  const cardCount = db.prepare('SELECT COUNT(*) AS c FROM all_cards WHERE owner_user_id = ?').get(req.user.user_id).c;
  const historyCount = db.prepare('SELECT COUNT(*) AS c FROM travel_history WHERE user_id = ? AND status = ?').get(req.user.user_id, 'success').c;
  const missionCount = db.prepare('SELECT COUNT(*) AS c FROM user_missions WHERE user_id = ?').get(req.user.user_id).c;
  res.json({ user: publicUser(req.user), stats: { cards: cardCount, places_visited: historyCount, missions_completed: missionCount } });
});

module.exports = router;
