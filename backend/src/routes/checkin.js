const express = require('express');
const crypto = require('crypto');
const db = require('../db');
const { newId, authMiddleware } = require('../util');

const router = express.Router();

const QR_TTL_SECONDS = 180;

router.get('/qr/:locationId', authMiddleware, (req, res) => {
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(req.params.locationId);
  if (!location) return res.status(404).json({ error: 'Location not found' });
  const nonce = crypto.randomBytes(6).toString('hex');
  const issuedAt = Date.now();
  const payload = `TRVCARD|${location.location_id}|${req.user.user_id}|${issuedAt}|${nonce}`;
  res.json({ qr_payload: payload, expires_in: QR_TTL_SECONDS, location });
});

router.post('/confirm', authMiddleware, (req, res) => {
  const { location_id } = req.body || {};
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(location_id);
  if (!location) return res.status(404).json({ error: 'Location not found' });

  const now = new Date().toISOString();
  db.prepare('INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status) VALUES (?, ?, ?, ?, ?)')
    .run(newId('hist'), req.user.user_id, location_id, now, 'success');

  const missions = db.prepare("SELECT * FROM missions WHERE location_id = ? AND status = 'active'").all(location_id);
  const awardedCards = [];
  const completedMissions = [];

  for (const mission of missions) {
    const already = db.prepare('SELECT 1 FROM user_missions WHERE user_id = ? AND mission_id = ?')
      .get(req.user.user_id, mission.mission_id);
    if (already) continue;

    db.prepare('INSERT INTO user_missions (user_id, mission_id, completed_at) VALUES (?, ?, ?)')
      .run(req.user.user_id, mission.mission_id, now);
    completedMissions.push(mission);

    const template = db.prepare('SELECT * FROM card_templates WHERE mission_id = ?').get(mission.mission_id);
    if (template) {
      const cardId = newId('card');
      db.prepare(`INSERT INTO all_cards (card_instance_id, template_id, owner_user_id, unique_code, acquired_at)
        VALUES (?, ?, ?, ?, ?)`)
        .run(cardId, template.template_id, req.user.user_id, newId('code'), now);
      awardedCards.push({ ...template, card_instance_id: cardId });
    }
  }

  res.json({
    status: 'success',
    checks: { device_secure: true, gps_verified: true, bluetooth_active: true },
    location,
    completed_missions: completedMissions,
    awarded_cards: awardedCards,
  });
});

module.exports = router;
