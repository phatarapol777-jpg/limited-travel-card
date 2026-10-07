const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');

const router = express.Router();

// Find a trade recipient by username or user id. Returns only a username and display name, never contact or face data.
router.get('/search', authMiddleware, (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 2 || q.length > 40) return res.json({ users: [] });
  const like = `%${q.replace(/[%_\\]/g, '\\$&')}%`;
  const rows = db.prepare(`SELECT user_id, username, first_name, last_name FROM users
    WHERE user_id != ? AND is_admin = 0 AND (username LIKE ? ESCAPE '\\' OR user_id = ?) ORDER BY username LIMIT 10`)
    .all(req.user.user_id, like, q);
  res.json({ users: rows.map((u) => ({ user_id: u.user_id, username: u.username, name: `${u.first_name} ${u.last_name}`.trim() })) });
});

module.exports = router;
