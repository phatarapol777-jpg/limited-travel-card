const express = require('express');
const db = require('../db');
const { newId, authMiddleware, adminMiddleware } = require('../util');
const { normalizeRarity } = require('../services/cardService');

const router = express.Router();
router.use(authMiddleware, adminMiddleware);

router.get('/locations', (req, res) => {
  const locations = db.prepare('SELECT * FROM locations ORDER BY name').all();
  const result = locations.map((loc) => {
    const mission = db.prepare('SELECT * FROM missions WHERE location_id = ?').get(loc.location_id);
    const row = mission ? db.prepare('SELECT * FROM card_templates WHERE mission_id = ?').get(mission.mission_id) : null;
    let card = null;
    if (row) {
      const { image, ...rest } = row; // the artwork is served by /api/media, never inside this list
      card = { ...rest, has_image: !!image };
    }
    const kiosk = db.prepare('SELECT * FROM checkin_kiosks WHERE location_id = ?').get(loc.location_id);
    return { ...loc, mission, card, kiosk };
  });
  res.json({ locations: result });
});

const { imageError, MAX_CARD_IMAGE_CHARS } = require('../services/questService');

/** Optional extras for a location's card: artwork, story and mint limit. Returns {error} or {extras}. */
function cardExtras(body, mintedCount = 0) {
  const b = body || {};
  const extras = {};
  if (typeof b.card_image === 'string' && b.card_image !== '') {
    const err = imageError(b.card_image, MAX_CARD_IMAGE_CHARS, 'ภาพการ์ด');
    if (err) return { error: err };
    extras.image = b.card_image;
  }
  if (b.remove_card_image === true) extras.image = null;
  if (b.card_lore !== undefined && b.card_lore !== null) {
    const lore = String(b.card_lore).trim();
    if (lore.length > 500) return { error: 'เรื่องราวการ์ดยาวเกิน 500 ตัวอักษร' };
    extras.lore = lore || null;
  }
  if (b.card_mint_limit !== undefined) {
    if (b.card_mint_limit === null || b.card_mint_limit === '') {
      extras.mint_limit = null;
    } else {
      const n = Number(b.card_mint_limit);
      if (!Number.isInteger(n) || n < 1 || n > 100000) return { error: 'จำนวนที่แจกสูงสุดต้องเป็นจำนวนเต็ม 1 ถึง 100,000 (เว้นว่าง = ไม่จำกัด)' };
      if (n < mintedCount) return { error: `ตั้งต่ำกว่าจำนวนที่แจกไปแล้ว (${mintedCount} ใบ) ไม่ได้` };
      extras.mint_limit = n;
    }
  }
  return { extras };
}

function applyCardExtras(templateId, extras) {
  const columns = ['image', 'lore', 'mint_limit'].filter((c) => extras[c] !== undefined);
  if (!columns.length) return;
  db.prepare(`UPDATE card_templates SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE template_id = ?`).run(...columns.map((c) => extras[c]), templateId);
}

function validateLocationPayload(body) {
  const { name, province, latitude, longitude, mission_title, card_name } = body || {};
  const blank = (v) => v === undefined || v === null || v === '';
  if (!name || !province || blank(latitude) || blank(longitude) || !mission_title || !card_name) {
    return 'กรุณากรอกข้อมูลให้ครบ: ชื่อสถานที่, จังหวัด, พิกัด, ชื่อภารกิจ, ชื่อการ์ด';
  }
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) return 'ละติจูดต้องอยู่ระหว่าง -90 ถึง 90 (ประเทศไทยประมาณ 5 ถึง 21)';
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) return 'ลองจิจูดต้องอยู่ระหว่าง -180 ถึง 180 (ประเทศไทยประมาณ 97 ถึง 106) ตรวจดูว่าไม่ได้ลืมจุดทศนิยม';
  return null;
}

router.post('/locations', (req, res) => {
  const err = validateLocationPayload(req.body);
  if (err) return res.status(400).json({ error: err });
  const parsed = cardExtras(req.body);
  if (parsed.error) return res.status(400).json({ error: parsed.error });

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
  db.prepare(`INSERT INTO checkin_kiosks (kiosk_id, location_id, mac_address, mock_ble_signal, status, kiosk_code)
    VALUES (?, ?, ?, ?, 'online', ?)`)
    .run(kioskId, locationId, `AA:BB:CC:${randomMacSuffix()}`, `BLE-BEACON-${locationId.slice(-4)}`, require('../services/kioskService').nextKioskCode());

  const missionId = newId('msn');
  db.prepare(`INSERT INTO missions (mission_id, location_id, title, description, end_date, status)
    VALUES (?, ?, ?, ?, NULL, 'active')`)
    .run(missionId, locationId, mission_title, mission_description || '');

  const templateId = newId('tpl');
  db.prepare(`INSERT INTO card_templates (template_id, location_id, mission_id, name, icon, color_hex, type, rarity, card_type)
    VALUES (?, ?, ?, ?, ?, ?, 'mission', ?, 'QUEST_LOCATION')`)
    .run(templateId, locationId, missionId, card_name, card_icon || 'style', card_color_hex || '#4C6B8A', normalizeRarity(card_rarity));

  applyCardExtras(templateId, parsed.extras);
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
  const existingMission = db.prepare('SELECT mission_id FROM missions WHERE location_id = ?').get(req.params.id);
  const existingCard = existingMission ? db.prepare('SELECT template_id, minted_count FROM card_templates WHERE mission_id = ?').get(existingMission.mission_id) : null;
  const parsed = cardExtras(req.body, existingCard ? existingCard.minted_count : 0);
  if (parsed.error) return res.status(400).json({ error: parsed.error });

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
        .run(card_name, card_icon || 'style', card_color_hex || '#4C6B8A', normalizeRarity(card_rarity), card.template_id);
      applyCardExtras(card.template_id, parsed.extras);
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
  const questCount = db.prepare('SELECT COUNT(*) AS c FROM quests WHERE location_id = ?').get(req.params.id).c;
  if (questCount > 0) {
    return res.status(400).json({ error: 'ลบไม่ได้ เพราะมีภารกิจที่สร้างไว้ที่สถานที่นี้' });
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

router.get('/stats', (req, res) => {
  const count = (sql) => db.prepare(sql).get().c;
  const topLocations = db.prepare(`SELECT l.name, l.province, COUNT(h.history_id) AS checkins
    FROM locations l LEFT JOIN travel_history h ON h.location_id = l.location_id AND h.status = 'success'
    GROUP BY l.location_id ORDER BY checkins DESC, l.name LIMIT 5`).all();
  res.json({
    users: count('SELECT COUNT(*) AS c FROM users WHERE is_admin = 0'),
    locations: count('SELECT COUNT(*) AS c FROM locations'),
    checkins: count("SELECT COUNT(*) AS c FROM travel_history WHERE status = 'success'"),
    cards_awarded: count('SELECT COUNT(*) AS c FROM all_cards WHERE owner_user_id IS NOT NULL'),
    booking_requests: count('SELECT COUNT(*) AS c FROM booking_requests'),
    kiosk_sessions_completed: count("SELECT COUNT(*) AS c FROM checkin_sessions WHERE status = 'completed'"),
    top_locations: topLocations,
  });
});

router.get('/users', (req, res) => {
  const users = db.prepare(`SELECT u.user_id, u.username, u.first_name, u.last_name, u.email, u.created_at,
      (SELECT COUNT(*) FROM all_cards c WHERE c.owner_user_id = u.user_id) AS cards,
      (SELECT COUNT(*) FROM travel_history t WHERE t.user_id = u.user_id AND t.status = 'success') AS checkins
    FROM users u WHERE u.is_admin = 0 ORDER BY u.created_at DESC`).all();
  res.json({ users });
});

router.get('/booking-requests', (req, res) => {
  const requests = db.prepare(`SELECT br.booking_request_id, br.guest_name, br.status, br.requested_at,
      u.username, ho.price_amount, ho.price_currency, ho.check_in_date, ho.check_out_date, h.name AS hotel_name
    FROM booking_requests br
    JOIN users u ON u.user_id = br.user_id
    JOIN hotel_offers ho ON ho.offer_id = br.offer_id
    JOIN hotels h ON h.hotel_id = ho.hotel_id
    ORDER BY br.requested_at DESC LIMIT 100`).all();
  res.json({ requests });
});

router.get('/checkins', (req, res) => {
  const checkins = db.prepare(`SELECT t.history_id, t.timestamp, u.username, l.name AS location_name, l.province,
      (SELECT s.session_id FROM checkin_sessions s WHERE s.user_id = t.user_id AND s.location_id = t.location_id AND s.face_photo IS NOT NULL ORDER BY s.created_at DESC LIMIT 1) AS photo_session_id
    FROM travel_history t JOIN users u ON u.user_id = t.user_id JOIN locations l ON l.location_id = t.location_id
    WHERE t.status = 'success' ORDER BY t.timestamp DESC LIMIT 100`).all();
  res.json({ checkins });
});

router.get('/kiosks', (req, res) => {
  const { kioskKey, ensureKioskCodes } = require('../services/kioskService');
  ensureKioskCodes();
  const rows = db.prepare(`SELECT k.kiosk_code, k.last_seen_at, l.name AS location_name, l.province
    FROM checkin_kiosks k JOIN locations l ON l.location_id = k.location_id ORDER BY k.kiosk_code`).all();
  res.json({ kiosks: rows.map((k) => ({ ...k, kiosk_key: kioskKey(k.kiosk_code) })) });
});

router.get('/audit', (req, res) => {
  const audit = db.prepare(`SELECT a.log_id, a.created_at, a.face_match_score, a.passed, a.edge_passed, a.edge_ms, a.reason, a.checks_json, a.session_id,
      u.username, k.kiosk_code, l.name AS location_name,
      (SELECT 1 FROM checkin_sessions s WHERE s.session_id = a.session_id AND s.face_photo IS NOT NULL) AS has_photo
    FROM checkin_audit a JOIN users u ON u.user_id = a.user_id JOIN checkin_kiosks k ON k.kiosk_id = a.kiosk_id
    JOIN locations l ON l.location_id = k.location_id ORDER BY a.created_at DESC LIMIT 100`).all();
  res.json({ audit });
});

// ---- quest requests: review, approve (creates the signed QR) or reject with a reason -------------------------------
router.get('/quests', (req, res) => {
  const { QUEST_SELECT, questView } = require('./quests');
  const status = ['pending', 'approved', 'rejected', 'closed'].includes(req.query.status) ? req.query.status : null;
  const rows = db.prepare(`${QUEST_SELECT} ${status ? 'WHERE q.status = ?' : ''} ORDER BY q.created_at DESC LIMIT 100`).all(...(status ? [status] : []));
  res.json({ quests: rows.map((q) => questView(q, { creator_username: q.creator_username })) });
});

router.get('/quests/:id/images', (req, res) => {
  const q = db.prepare('SELECT q.cover_image, t.image AS card_image FROM quests q LEFT JOIN card_templates t ON t.template_id = q.template_id WHERE q.quest_id = ?').get(req.params.id);
  if (!q) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  res.json({ cover_image: q.cover_image, card_image: q.card_image });
});

router.post('/quests/:id/approve', (req, res) => {
  const q = db.prepare('SELECT * FROM quests WHERE quest_id = ?').get(req.params.id);
  if (!q) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  if (q.status !== 'pending') return res.status(409).json({ error: 'ภารกิจนี้ถูกพิจารณาไปแล้ว' });
  db.prepare("UPDATE quests SET status = 'approved', reject_reason = NULL, reviewed_at = ?, reviewed_by = ? WHERE quest_id = ?")
    .run(new Date().toISOString(), req.user.user_id, q.quest_id);
  require('../services/notify').notify(q.creator_user_id, 'quest_approved', `ภารกิจ "${q.title}" ได้รับอนุมัติแล้ว ดาวน์โหลด QR Code ไปติดที่สถานที่ได้เลย`, { quest_id: q.quest_id });
  res.json({ status: 'approved' });
});

router.post('/quests/:id/reject', (req, res) => {
  const reason = String((req.body || {}).reason || '').trim();
  if (!reason || reason.length > 500) return res.status(400).json({ error: 'กรุณาระบุเหตุผลที่ไม่อนุมัติ (ไม่เกิน 500 ตัวอักษร)' });
  const q = db.prepare('SELECT * FROM quests WHERE quest_id = ?').get(req.params.id);
  if (!q) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  if (q.status !== 'pending') return res.status(409).json({ error: 'ภารกิจนี้ถูกพิจารณาไปแล้ว' });
  db.prepare("UPDATE quests SET status = 'rejected', reject_reason = ?, reviewed_at = ?, reviewed_by = ? WHERE quest_id = ?")
    .run(reason, new Date().toISOString(), req.user.user_id, q.quest_id);
  require('../services/notify').notify(q.creator_user_id, 'quest_rejected', `ภารกิจ "${q.title}" ไม่ได้รับอนุมัติ: ${reason}`, { quest_id: q.quest_id });
  res.json({ status: 'rejected' });
});

router.post('/quests/:id/close', (req, res) => {
  const q = db.prepare('SELECT * FROM quests WHERE quest_id = ?').get(req.params.id);
  if (!q) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  if (q.status !== 'approved') return res.status(409).json({ error: 'ปิดได้เฉพาะภารกิจที่อนุมัติแล้ว' });
  db.prepare("UPDATE quests SET status = 'closed' WHERE quest_id = ?").run(q.quest_id);
  res.json({ status: 'closed' });
});

// ---- physical blind-pack cards: a master card plus a batch of unclaimed cards, each with its own activation QR --------
router.post('/blind-packs', (req, res) => {
  const { mintCard } = require('../services/cardService');
  const b = req.body || {};
  const name = String(b.name || '').trim();
  const lore = String(b.lore || '').trim();
  const count = Number(b.count);
  if (!name || name.length > 60) return res.status(400).json({ error: 'ชื่อการ์ดต้องไม่ว่างและไม่เกิน 60 ตัวอักษร' });
  if (lore.length > 500) return res.status(400).json({ error: 'เรื่องราวการ์ดยาวเกิน 500 ตัวอักษร' });
  if (!['normal', 'rare', 'special'].includes(String(b.rarity || '').toLowerCase())) return res.status(400).json({ error: 'เลือกระดับความหายาก' });
  if (!Number.isInteger(count) || count < 1 || count > 5000) return res.status(400).json({ error: 'จำนวนการ์ดต้องเป็นจำนวนเต็ม 1 ถึง 5,000' });
  const { imageError, MAX_CARD_IMAGE_CHARS } = require('../services/questService');
  const imgErr = b.card_image ? imageError(b.card_image, MAX_CARD_IMAGE_CHARS, 'ภาพการ์ด') : null;
  if (imgErr) return res.status(400).json({ error: imgErr });

  const templateId = newId('tpl');
  const created = db.transaction(() => {
    db.prepare(`INSERT INTO card_templates (template_id, location_id, mission_id, name, icon, color_hex, type, rarity, card_type, image, lore, mint_limit, minted_count, quest_id)
      VALUES (?, NULL, NULL, ?, 'style', ?, 'random', ?, 'PHYSICAL_BLIND_PACK', ?, ?, ?, 0, NULL)`)
      .run(templateId, name, /^#[0-9A-Fa-f]{6}$/.test(b.color_hex || '') ? b.color_hex : '#4C6B8A', normalizeRarity(b.rarity), b.card_image || null, lore || null, count);
    for (let i = 0; i < count; i++) mintCard({ templateId, userId: null, withActivationCode: true });
  })();
  void created;
  res.status(201).json({ template_id: templateId, count });
});

router.get('/blind-packs', (req, res) => {
  const rows = db.prepare(`SELECT t.template_id, t.name, t.rarity, t.mint_limit, t.minted_count,
      (SELECT COUNT(*) FROM all_cards c WHERE c.template_id = t.template_id AND c.activation_status != 'UNCLAIMED') AS claimed
    FROM card_templates t WHERE t.card_type = 'PHYSICAL_BLIND_PACK' AND EXISTS (SELECT 1 FROM all_cards c WHERE c.template_id = t.template_id AND c.activation_code IS NOT NULL)
    ORDER BY t.name`).all();
  res.json({ packs: rows });
});

// The activation codes to print as QR codes on the physical cards (admin only: each code is a bearer credential).
router.get('/blind-packs/:id/codes', (req, res) => {
  const { serialLabel } = require('../services/cardService');
  const t = db.prepare("SELECT * FROM card_templates WHERE template_id = ? AND card_type = 'PHYSICAL_BLIND_PACK'").get(req.params.id);
  if (!t) return res.status(404).json({ error: 'ไม่พบการ์ด' });
  const cards = db.prepare("SELECT serial_number, activation_code, activation_status FROM all_cards WHERE template_id = ? AND activation_code IS NOT NULL ORDER BY serial_number").all(t.template_id);
  res.json({
    name: t.name,
    codes: cards.map((c) => ({ serial: serialLabel(c.serial_number, t.mint_limit), payload: `TRVCARD|${c.activation_code}`, status: c.activation_status })),
  });
});

// How many people tapped "order physical card" for each design.
router.get('/order-intents', (req, res) => {
  const rows = db.prepare(`SELECT t.template_id, t.name, t.rarity, COUNT(i.intent_id) AS interested, MAX(i.created_at) AS last_at
    FROM physical_order_intents i JOIN card_templates t ON t.template_id = i.template_id GROUP BY t.template_id ORDER BY interested DESC, last_at DESC`).all();
  res.json({ intents: rows });
});

router.get('/kiosk-sessions/:id/photo', (req, res) => {
  const row = db.prepare('SELECT face_photo FROM checkin_sessions WHERE session_id = ?').get(req.params.id);
  if (!row || !row.face_photo) return res.status(404).json({ error: 'ไม่พบภาพ' });
  res.json({ photo: row.face_photo });
});

router.put('/booking-requests/:id/status', (req, res) => {
  const { status } = req.body || {};
  if (!['requested', 'confirmed', 'rejected'].includes(status)) return res.status(400).json({ error: 'สถานะไม่ถูกต้อง' });
  const result = db.prepare('UPDATE booking_requests SET status = ? WHERE booking_request_id = ?').run(status, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'ไม่พบคำขอจองนี้' });
  res.json({ status });
});

module.exports = router;
