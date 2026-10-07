const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');

const router = express.Router();

router.get('/', authMiddleware, (req, res) => {
  const rows = db.prepare('SELECT notification_id, type, text, data_json, read_at, created_at FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').all(req.user.user_id);
  const unread = db.prepare('SELECT COUNT(*) AS c FROM notifications WHERE user_id = ? AND read_at IS NULL').get(req.user.user_id).c;
  res.json({ unread, notifications: rows.map((r) => ({ ...r, data: r.data_json ? JSON.parse(r.data_json) : null, data_json: undefined })) });
});

router.post('/read', authMiddleware, (req, res) => {
  db.prepare('UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL').run(new Date().toISOString(), req.user.user_id);
  res.json({ ok: true });
});

module.exports = router;
