const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');
const { CARD_SELECT, cardView } = require('../services/cardService');

const router = express.Router();

// Find a trade recipient by username or user id. Returns only a username and display name, never contact or face data.
router.get('/search', authMiddleware, (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 2 || q.length > 40) return res.json({ users: [] });
  const like = `%${q.replace(/[%_\\]/g, '\\$&')}%`;
  const rows = db.prepare(`SELECT user_id, username, display_name FROM users
    WHERE user_id != ? AND is_admin = 0 AND username NOT LIKE 'deleted-%' AND (username LIKE ? ESCAPE '\\' OR display_name LIKE ? ESCAPE '\\' OR user_id = ?) ORDER BY username LIMIT 10`)
    .all(req.user.user_id, like, like, q);
  res.json({ users: rows.map((u) => ({ user_id: u.user_id, username: u.username, name: u.display_name || u.username })) });
});

// The cards a traveler could trade right now (activated and not locked in another offer): used to pick a swap target.
router.get('/:username/cards', authMiddleware, (req, res) => {
  const user = db.prepare('SELECT user_id FROM users WHERE username = ? AND is_admin = 0').get(req.params.username);
  if (!user) return res.status(404).json({ error: 'ไม่พบผู้ใช้' });
  const cards = db.prepare(`${CARD_SELECT} WHERE c.owner_user_id = ? AND c.activation_status = 'CLAIMED' ORDER BY c.acquired_at DESC`).all(user.user_id).map(cardView);
  res.json({ cards });
});

module.exports = router;
