const express = require('express');
const db = require('../db');
const { newId, authMiddleware, adminMiddleware } = require('../util');

const router = express.Router();
router.use(authMiddleware, adminMiddleware);

router.get('/locations', (req, res) => {
  const locations = db.prepare('SELECT * FROM locations ORDER BY name').all();
  const result = locations.map((loc) => {
    const mission = db.prepare('SELECT * FROM missions WHERE location_id = ?').get(loc.location_id);
    const card = mission ? db.prepare('SELECT * FROM card_templates WHERE mission_id = ?').get(mission.mission_id) : null;
    const kiosk = db.prepare('SELECT * FROM checkin_kiosks WHERE location_id = ?').get(loc.location_id);
    return { ...loc, mission, card, kiosk };
  });
  res.json({ locations: result });
});

function validateLocationPayload(body) {
  const { name, province, latitude, longitude, mission_title, card_name } = body || {};
  if (!name || !province || latitude === undefined || longitude === undefined || !mission_title || !card_name) {
    return 'กรุณากรอกข้อมูลให้ครบ: ชื่อสถานที่, จังหวัด, พิกัด, ชื่อภารกิจ, ชื่อการ์ด';
  }
  return null;
}

router.post('/locations', (req, res) => {
  const err = validateLocationPayload(req.body);
  if (err) return res.status(400).json({ error: err });

  const {
    name, description, latitude, longitude, province, icon,
    mission_title, mission_description,
    card_name, card_icon, card_color_hex, card_rarity,
  } = req.body;

  const now = new Date().toISOString();
  const locationId = newId('loc');
  db.prepare(`INSERT INTO locations (location_id, name, description, latitude, longitude, province, icon, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(locationId, name, description || null, latitude, longitude, province, icon || 'place', now);

  const kioskId = newId('kiosk');
  db.prepare(`INSERT INTO checkin_kiosks (kiosk_id, location_id, mac_address, mock_ble_signal, status)
    VALUES (?, ?, ?, ?, 'online')`)
    .run(kioskId, locationId, `AA:BB:CC:${randomMacSuffix()}`, `BLE-BEACON-${locationId.slice(-4)}`);

  const missionId = newId('msn');
  db.prepare(`INSERT INTO missions (mission_id, location_id, title, description, end_date, status)
    VALUES (?, ?, ?, ?, NULL, 'active')`)
    .run(missionId, locationId, mission_title, mission_description || '');

  const templateId = newId('tpl');
  db.prepare(`INSERT INTO card_templates (template_id, location_id, mission_id, name, icon, color_hex, type, rarity)
    VALUES (?, ?, ?, ?, ?, ?, 'mission', ?)`)
    .run(templateId, locationId, missionId, card_name, card_icon || 'style', card_color_hex || '#4C6B8A', card_rarity || 'common');

  res.status(201).json({ location_id: locationId, mission_id: missionId, template_id: templateId, kiosk_id: kioskId });
});

function randomMacSuffix() {
  return Math.floor(Math.random() * 0xffff).toString(16).padStart(4, '0').slice(0, 2) + ':' +
    Math.floor(Math.random() * 0xffff).toString(16).padStart(4, '0').slice(0, 2);
}

router.put('/locations/:id', (req, res) => {
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(req.params.id);
  if (!location) return res.status(404).json({ error: 'ไม่พบสถานที่นี้' });

  const err = validateLocationPayload(req.body);
  if (err) return res.status(400).json({ error: err });

  const {
    name, description, latitude, longitude, province, icon,
    mission_title, mission_description,
    card_name, card_icon, card_color_hex, card_rarity,
  } = req.body;

  db.prepare(`UPDATE locations SET name = ?, description = ?, latitude = ?, longitude = ?, province = ?, icon = ?
    WHERE location_id = ?`)
    .run(name, description || null, latitude, longitude, province, icon || 'place', req.params.id);

  const mission = db.prepare('SELECT * FROM missions WHERE location_id = ?').get(req.params.id);
  if (mission) {
    db.prepare('UPDATE missions SET title = ?, description = ? WHERE mission_id = ?')
      .run(mission_title, mission_description || '', mission.mission_id);

    const card = db.prepare('SELECT * FROM card_templates WHERE mission_id = ?').get(mission.mission_id);
    if (card) {
      db.prepare('UPDATE card_templates SET name = ?, icon = ?, color_hex = ?, rarity = ? WHERE template_id = ?')
        .run(card_name, card_icon || 'style', card_color_hex || '#4C6B8A', card_rarity || 'common', card.template_id);
    }
  }

  res.json({ status: 'updated' });
});

router.delete('/locations/:id', (req, res) => {
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(req.params.id);
  if (!location) return res.status(404).json({ error: 'ไม่พบสถานที่นี้' });

  const historyCount = db.prepare('SELECT COUNT(*) AS c FROM travel_history WHERE location_id = ?').get(req.params.id).c;
  const mission = db.prepare('SELECT * FROM missions WHERE location_id = ?').get(req.params.id);
  let cardOwnedCount = 0;
  let template = null;
  if (mission) {
    template = db.prepare('SELECT * FROM card_templates WHERE mission_id = ?').get(mission.mission_id);
    if (template) {
      cardOwnedCount = db.prepare('SELECT COUNT(*) AS c FROM all_cards WHERE template_id = ?').get(template.template_id).c;
    }
  }
  if (historyCount > 0 || cardOwnedCount > 0) {
    return res.status(400).json({ error: 'ลบไม่ได้ เพราะมีนักท่องเที่ยวเช็คอินหรือได้รับการ์ดจากสถานที่นี้แล้ว' });
  }

  db.prepare('DELETE FROM checkin_sessions WHERE location_id = ?').run(req.params.id);
  db.prepare('DELETE FROM checkin_kiosks WHERE location_id = ?').run(req.params.id);
  if (template) db.prepare('DELETE FROM card_templates WHERE template_id = ?').run(template.template_id);
  if (mission) db.prepare('DELETE FROM missions WHERE mission_id = ?').run(mission.mission_id);
  db.prepare('DELETE FROM locations WHERE location_id = ?').run(req.params.id);

  res.json({ status: 'deleted' });
});

module.exports = router;
