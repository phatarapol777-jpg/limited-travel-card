const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');
const { statsFor, pinsFor, OWNED } = require('../services/profileService');

const router = express.Router();
const MAX_PINS = 5;

function profileOf(user) {
  return {
    user: { user_id: user.user_id, username: user.username, name: user.display_name || user.username },
    pins: pinsFor(user.user_id),
    stats: statsFor(user.user_id),
  };
}

// Choose the 3-5 cards shown at the top of the profile (the order is kept).
router.put('/pins', authMiddleware, (req, res) => {
  const ids = (req.body || {}).card_instance_ids;
  if (!Array.isArray(ids) || ids.length > MAX_PINS || ids.some((x) => typeof x !== 'string') || new Set(ids).size !== ids.length) {
    return res.status(400).json({ error: `เลือกการ์ดได้สูงสุด ${MAX_PINS} ใบ และห้ามซ้ำกัน` });
  }
  for (const id of ids) {
    const card = db.prepare(`SELECT c.card_instance_id FROM all_cards c WHERE c.card_instance_id = ? AND ${OWNED}`).get(id, req.user.user_id);
    if (!card) return res.status(400).json({ error: 'ปักหมุดได้เฉพาะการ์ดที่คุณถือครองอยู่' });
  }
  db.transaction(() => {
    db.prepare('DELETE FROM user_pins WHERE user_id = ?').run(req.user.user_id);
    ids.forEach((id, i) => db.prepare('INSERT INTO user_pins (user_id, card_instance_id, position) VALUES (?, ?, ?)').run(req.user.user_id, id, i));
  })();
  res.json({ pins: pinsFor(req.user.user_id) });
});

router.get('/me', authMiddleware, (req, res) => {
  res.json(profileOf(req.user));
});

// Any signed-in user can look at another traveler's showcase (name, pinned cards, statistics; no contact details).
router.get('/:username', authMiddleware, (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE username = ? AND is_admin = 0').get(req.params.username);
  if (!user) return res.status(404).json({ error: 'ไม่พบผู้ใช้' });
  res.json(profileOf(user));
});

module.exports = router;
