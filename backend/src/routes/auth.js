const express = require('express');
const db = require('../db');
const { newId, hashPassword, verifyPassword, createSession, authMiddleware, publicUser } = require('../util');

const router = express.Router();

router.post('/register', (req, res) => {
  const { username, password, first_name, last_name, email, phone, face_data } = req.body || {};
  if (!username || !password || !first_name || !last_name || !email) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  const existing = db.prepare('SELECT 1 FROM users WHERE username = ? OR email = ?').get(username, email);
  if (existing) return res.status(409).json({ error: 'Username or email already exists' });

  const userId = newId('usr');
  const { hash, salt } = hashPassword(password);
  db.prepare(`INSERT INTO users (user_id, username, password_hash, password_salt, first_name, last_name, email, phone, face_data, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(userId, username, hash, salt, first_name, last_name, email, phone || null, face_data || 'captured', new Date().toISOString());

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

router.get('/me', authMiddleware, (req, res) => {
  const cardCount = db.prepare('SELECT COUNT(*) AS c FROM all_cards WHERE owner_user_id = ?').get(req.user.user_id).c;
  const historyCount = db.prepare('SELECT COUNT(*) AS c FROM travel_history WHERE user_id = ? AND status = ?').get(req.user.user_id, 'success').c;
  const missionCount = db.prepare('SELECT COUNT(*) AS c FROM user_missions WHERE user_id = ?').get(req.user.user_id).c;
  res.json({ user: publicUser(req.user), stats: { cards: cardCount, places_visited: historyCount, missions_completed: missionCount } });
});

module.exports = router;
