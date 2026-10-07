const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');

const router = express.Router();

router.get('/locations', (req, res) => {
  // card_image_rev changes whenever the picture is replaced, so clients can cache it by URL
  const rows = db.prepare(`SELECT l.*, t.template_id AS card_template_id, length(t.image) AS card_image_rev
    FROM locations l
    LEFT JOIN missions m ON m.location_id = l.location_id
    LEFT JOIN card_templates t ON t.mission_id = m.mission_id
    GROUP BY l.location_id ORDER BY l.name`).all();
  const locations = rows.map((r) => ({ ...r, card_has_image: !!r.card_image_rev, card_image_rev: r.card_image_rev || 0 }));
  res.json({ locations });
});

router.get('/locations/:id', (req, res) => {
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(req.params.id);
  if (!location) return res.status(404).json({ error: 'Not found' });
  const missions = db.prepare('SELECT * FROM missions WHERE location_id = ?').all(req.params.id);
  const shops = db.prepare('SELECT * FROM shops WHERE location_id = ?').all(req.params.id);
  res.json({ location, missions, shops });
});

router.get('/kiosks', (req, res) => {
  const kiosks = db.prepare(`SELECT k.kiosk_id, k.kiosk_code, k.location_id, k.status, l.name AS location_name, l.province
    FROM checkin_kiosks k JOIN locations l ON l.location_id = k.location_id ORDER BY l.name`).all();
  res.json({ kiosks });
});

router.get('/shops', (req, res) => {
  const shops = db.prepare(`SELECT s.*, l.name AS location_name FROM shops s
    LEFT JOIN locations l ON l.location_id = s.location_id ORDER BY s.rating DESC`).all();
  res.json({ shops });
});

router.get('/missions', (req, res) => {
  const rows = db.prepare(`SELECT m.*, l.name AS location_name, l.province AS location_province
    FROM missions m JOIN locations l ON l.location_id = m.location_id ORDER BY m.title`).all();

  let completedSet = new Set();
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (token) {
    const session = db.prepare('SELECT user_id FROM sessions WHERE token = ?').get(token);
    if (session) {
      completedSet = new Set(
        db.prepare('SELECT mission_id FROM user_missions WHERE user_id = ?').all(session.user_id).map((r) => r.mission_id),
      );
    }
  }
  const missions = rows.map((m) => ({ ...m, completed: completedSet.has(m.mission_id) }));
  res.json({ missions });
});

module.exports = router;
