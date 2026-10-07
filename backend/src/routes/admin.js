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
  const shopCount = db.prepare('SELECT COUNT(*) AS c FROM merchants WHERE nearby_location_id = ?').get(req.params.id).c;
  if (shopCount > 0) {
    return res.status(400).json({ error: 'ลบไม่ได้ เพราะมีร้านค้าพันธมิตรที่ผูกกับสถานที่นี้' });
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
  const byStatus = (table, column, statuses) => Object.fromEntries(statuses.map((st) => [st.toLowerCase(), count(`SELECT COUNT(*) AS c FROM ${table} WHERE ${column} = '${st}'`)]));
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
    // read-only summary of the newer modules (the PHP admin shows it; review and moderation stay in the Node dashboard)
    modules: {
      quests: byStatus('quests', 'status', ['pending', 'approved', 'rejected', 'closed']),
      merchants: {
        ...byStatus('merchants', 'approval_status', ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED']),
        revisions_waiting: count('SELECT COUNT(*) AS c FROM merchants WHERE pending_revision IS NOT NULL'),
        with_privileges: count("SELECT COUNT(DISTINCT p.merchant_id) AS c FROM merchant_privileges p JOIN merchants m ON m.merchant_id = p.merchant_id WHERE m.approval_status = 'APPROVED'"),
      },
      blind_packs: {
        designs: count("SELECT COUNT(*) AS c FROM card_templates WHERE card_type = 'PHYSICAL_BLIND_PACK'"),
        order_interest: count('SELECT COUNT(*) AS c FROM physical_order_intents'),
      },
      community: {
        posts: count("SELECT COUNT(*) AS c FROM community_posts WHERE status = 'visible'"),
        hidden_posts: count("SELECT COUNT(*) AS c FROM community_posts WHERE status = 'hidden'"),
        comments: count('SELECT COUNT(*) AS c FROM community_comments'),
        reactions: count('SELECT COUNT(*) AS c FROM post_reactions'),
        follows: count('SELECT COUNT(*) AS c FROM follows'),
        reported_posts: count('SELECT COUNT(DISTINCT post_id) AS c FROM post_reports'),
        badges_awarded: count('SELECT COUNT(*) AS c FROM user_badges'),
      },
      cards_voided: count("SELECT COUNT(*) AS c FROM all_cards WHERE activation_status = 'VOIDED'"),
    },
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
  const rows = db.prepare(`SELECT k.kiosk_code, k.last_seen_at, k.key_version, k.disabled, l.name AS location_name, l.province
    FROM checkin_kiosks k JOIN locations l ON l.location_id = k.location_id ORDER BY k.kiosk_code`).all();
  res.json({ kiosks: rows.map((k) => ({ ...k, disabled: !!k.disabled, kiosk_key: kioskKey(k.kiosk_code, k.key_version) })) });
});

// A leaked key: give the kiosk a new one (the old one stops working at once and any open session there is ended).
router.post('/kiosks/:code/rotate-key', (req, res) => {
  const { kioskKey } = require('../services/kioskService');
  const k = db.prepare('SELECT * FROM checkin_kiosks WHERE kiosk_code = ?').get(req.params.code);
  if (!k) return res.status(404).json({ error: 'ไม่พบตู้' });
  db.transaction(() => {
    db.prepare('UPDATE checkin_kiosks SET key_version = key_version + 1 WHERE kiosk_id = ?').run(k.kiosk_id);
    db.prepare("UPDATE checkin_sessions SET status = 'expired' WHERE kiosk_id = ? AND status = 'open'").run(k.kiosk_id);
  })();
  res.json({ kiosk_code: k.kiosk_code, kiosk_key: kioskKey(k.kiosk_code, k.key_version + 1) });
});

function setKioskDisabled(disable) {
  return (req, res) => {
    const k = db.prepare('SELECT * FROM checkin_kiosks WHERE kiosk_code = ?').get(req.params.code);
    if (!k) return res.status(404).json({ error: 'ไม่พบตู้' });
    db.transaction(() => {
      db.prepare('UPDATE checkin_kiosks SET disabled = ? WHERE kiosk_id = ?').run(disable ? 1 : 0, k.kiosk_id);
      if (disable) db.prepare("UPDATE checkin_sessions SET status = 'expired' WHERE kiosk_id = ? AND status = 'open'").run(k.kiosk_id);
    })();
    res.json({ kiosk_code: k.kiosk_code, disabled: disable });
  };
}
router.post('/kiosks/:code/disable', setKioskDisabled(true));
router.post('/kiosks/:code/enable', setKioskDisabled(false));

router.get('/audit', (req, res) => {
  const audit = db.prepare(`SELECT a.log_id, a.created_at, a.face_match_score, a.passed, a.edge_passed, a.edge_ms, a.reason, a.checks_json, a.session_id,
      u.username, k.kiosk_code, l.name AS location_name,
      (SELECT 1 FROM checkin_sessions s WHERE s.session_id = a.session_id AND s.face_photo IS NOT NULL) AS has_photo
    FROM checkin_audit a JOIN users u ON u.user_id = a.user_id JOIN checkin_kiosks k ON k.kiosk_id = a.kiosk_id
    JOIN locations l ON l.location_id = k.location_id ORDER BY a.created_at DESC LIMIT 100`).all();
  res.json({ audit });
});

router.get('/settings', (req, res) => {
  res.json({ settings: require('../services/settings').all() });
});

router.put('/settings', (req, res) => {
  const settings = require('../services/settings');
  const changes = req.body || {};
  for (const [key, value] of Object.entries(changes)) {
    const err = settings.set(key, value);
    if (err) return res.status(400).json({ error: `${key}: ${err}` });
  }
  res.json({ settings: settings.all() });
});

router.get('/backup-status', (req, res) => {
  res.json(require('../services/backup').status());
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

// ---- cards: search and void -----------------------------------------------------------------------------------------
router.get('/cards', (req, res) => {
  const { CARD_SELECT, cardView } = require('../services/cardService');
  const q = String(req.query.q || '').trim().slice(0, 60);
  const like = `%${q.replace(/[%_\\]/g, '\\$&')}%`;
  const rows = db.prepare(`${CARD_SELECT} LEFT JOIN users ou ON ou.user_id = c.owner_user_id
    ${q ? "WHERE (ou.username LIKE ? ESCAPE '\\' OR t.name LIKE ? ESCAPE '\\')" : ''} ORDER BY c.rowid DESC LIMIT 100`)
    .all(...(q ? [like, like] : []));
  const owners = new Map(db.prepare('SELECT user_id, username FROM users').all().map((u) => [u.user_id, u.username]));
  res.json({ cards: rows.map((r) => ({ ...cardView(r), owner_username: owners.get(r.owner_user_id) || null })) });
});

// Cancel a card for good (misprinted, lost, fraudulent). It leaves the owner's collection, showcase and any pending trade.
router.post('/cards/:id/void', (req, res) => {
  const { resolveTrade } = require('../services/tradeService');
  const { notify } = require('../services/notify');
  const { logOwnership } = require('../services/cardService');
  const reason = String((req.body || {}).reason || '').trim().slice(0, 300);
  const card = db.prepare('SELECT c.*, t.name FROM all_cards c JOIN card_templates t ON t.template_id = c.template_id WHERE c.card_instance_id = ?').get(req.params.id);
  if (!card) return res.status(404).json({ error: 'ไม่พบการ์ด' });
  if (card.activation_status === 'VOIDED') return res.status(409).json({ error: 'การ์ดใบนี้ถูกยกเลิกไปแล้ว' });
  db.transaction(() => {
    for (const t of db.prepare("SELECT * FROM trades WHERE status = 'pending' AND (offered_card_id = ? OR requested_card_id = ?)").all(card.card_instance_id, card.card_instance_id)) {
      resolveTrade(t, 'cancelled');
      for (const uid of [t.from_user_id, t.to_user_id]) notify(uid, 'trade_cancelled', 'ข้อเสนอแลกเปลี่ยนถูกยกเลิก เพราะการ์ดในข้อเสนอถูกยกเลิกโดยผู้ดูแล', { trade_id: t.trade_id });
    }
    db.prepare("UPDATE all_cards SET activation_status = 'VOIDED' WHERE card_instance_id = ?").run(card.card_instance_id);
    db.prepare('DELETE FROM user_pins WHERE card_instance_id = ?').run(card.card_instance_id);
    logOwnership(card.card_instance_id, card.owner_user_id, null, 'void');
    if (card.owner_user_id) notify(card.owner_user_id, 'card_voided', `การ์ด "${card.name}" ของคุณถูกยกเลิกโดยผู้ดูแลระบบ${reason ? ': ' + reason : ''}`, { card_instance_id: card.card_instance_id });
  })();
  res.json({ status: 'voided' });
});

// Tell the people who tapped "order physical card" that it is ready. Idempotent: each person is told once.
router.post('/order-intents/:templateId/notify', (req, res) => {
  const { notify } = require('../services/notify');
  const t = db.prepare('SELECT name FROM card_templates WHERE template_id = ?').get(req.params.templateId);
  if (!t) return res.status(404).json({ error: 'ไม่พบการ์ด' });
  const custom = String((req.body || {}).message || '').trim().slice(0, 300);
  const text = custom || `การ์ด "${t.name}" ที่คุณสนใจพร้อมจัดส่งแล้ว ติดต่อผู้ดูแลเพื่อสั่งซื้อได้เลย`;
  const pending = db.prepare('SELECT intent_id, user_id FROM physical_order_intents WHERE template_id = ? AND notified_at IS NULL').all(req.params.templateId);
  const now = new Date().toISOString();
  db.transaction(() => {
    for (const i of pending) {
      notify(i.user_id, 'order_ready', text, { template_id: req.params.templateId });
      db.prepare('UPDATE physical_order_intents SET notified_at = ? WHERE intent_id = ?').run(now, i.intent_id);
    }
  })();
  res.json({ notified: pending.length });
});

// ---- partner shops: review, approve (a first submission or a change to a live shop), reject, suspend ----------------------------
router.get('/merchants', (req, res) => {
  const status = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'].includes(req.query.status) ? req.query.status : null;
  const rows = db.prepare(`SELECT m.merchant_id, m.shop_name_th, m.shop_name_en, m.category, m.approval_status, m.reject_reason, m.created_at, m.updated_at,
      (m.pending_revision IS NOT NULL) AS has_revision, m.address_detail, m.latitude, m.longitude, u.username AS owner_username
    FROM merchants m JOIN users u ON u.user_id = m.owner_user_id
    WHERE ${status === 'PENDING' ? "(m.approval_status = 'PENDING' OR m.pending_revision IS NOT NULL)" : status ? 'm.approval_status = ?' : '1 = 1'}
    ORDER BY (m.approval_status = 'PENDING' OR m.pending_revision IS NOT NULL) DESC, m.updated_at DESC LIMIT 100`)
    .all(...(status && status !== 'PENDING' ? [status] : []));
  res.json({ merchants: rows.map((r) => ({ ...r, has_revision: !!r.has_revision })) });
});

function withCardNames(form) {
  const name = db.prepare('SELECT name FROM card_templates WHERE template_id = ?');
  return { ...form, privileges: (form.privileges || []).map((p) => ({ ...p, template_name: (name.get(p.template_id) || {}).name || null })) };
}

router.get('/merchants/:id', (req, res) => {
  const M = require('../services/merchantService');
  const m = db.prepare('SELECT m.*, u.username AS owner_username FROM merchants m JOIN users u ON u.user_id = m.owner_user_id WHERE m.merchant_id = ?').get(req.params.id);
  if (!m) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  res.json({
    merchant_id: m.merchant_id, owner_username: m.owner_username, status: m.approval_status, reject_reason: m.reject_reason,
    reviewing: m.pending_revision ? 'revision' : 'new', form: withCardNames(M.currentForm(m.merchant_id)),
  });
});

router.post('/merchants/:id/approve', (req, res) => {
  const M = require('../services/merchantService');
  const { notify } = require('../services/notify');
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  const isRevision = m.approval_status === 'APPROVED' && m.pending_revision;
  if (m.approval_status !== 'PENDING' && !isRevision) return res.status(409).json({ error: 'ร้านนี้ไม่มีอะไรรออนุมัติ' });
  db.transaction(() => {
    if (m.pending_revision) M.applyForm(m.merchant_id, JSON.parse(m.pending_revision));
    db.prepare("UPDATE merchants SET approval_status = 'APPROVED', reject_reason = NULL, pending_revision = NULL, revision_note = NULL, reviewed_at = ?, reviewed_by = ? WHERE merchant_id = ?")
      .run(new Date().toISOString(), req.user.user_id, m.merchant_id);
  })();
  notify(m.owner_user_id, 'merchant_approved', isRevision ? `การแก้ไขร้าน "${m.shop_name_th}" ได้รับอนุมัติแล้ว` : `ร้าน "${m.shop_name_th}" ได้รับอนุมัติ หมุดร้านขึ้นบนแผนที่แล้ว`, { merchant_id: m.merchant_id });
  res.json({ status: 'APPROVED' });
});

router.post('/merchants/:id/reject', (req, res) => {
  const { notify } = require('../services/notify');
  const reason = String((req.body || {}).reason || '').trim();
  if (!reason || reason.length > 500) return res.status(400).json({ error: 'กรุณาระบุข้อแก้ไข/เหตุผล (ไม่เกิน 500 ตัวอักษร)' });
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  const now = new Date().toISOString();
  if (m.approval_status === 'APPROVED' && m.pending_revision) {
    // a rejected change: the shop stays live as it was, the owner is told what to fix
    db.prepare('UPDATE merchants SET pending_revision = NULL, revision_note = ?, reviewed_at = ?, reviewed_by = ? WHERE merchant_id = ?').run(reason, now, req.user.user_id, m.merchant_id);
  } else if (m.approval_status === 'PENDING') {
    db.prepare("UPDATE merchants SET approval_status = 'REJECTED', reject_reason = ?, reviewed_at = ?, reviewed_by = ? WHERE merchant_id = ?").run(reason, now, req.user.user_id, m.merchant_id);
  } else {
    return res.status(409).json({ error: 'ร้านนี้ไม่มีอะไรรออนุมัติ' });
  }
  notify(m.owner_user_id, 'merchant_rejected', `ร้าน "${m.shop_name_th}" ต้องแก้ไข: ${reason}`, { merchant_id: m.merchant_id });
  res.json({ status: 'rejected' });
});

router.post('/merchants/:id/suspend', (req, res) => {
  const { notify } = require('../services/notify');
  const reason = String((req.body || {}).reason || '').trim().slice(0, 300);
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  if (m.approval_status !== 'APPROVED') return res.status(409).json({ error: 'ระงับได้เฉพาะร้านที่เปิดใช้งานอยู่' });
  db.prepare("UPDATE merchants SET approval_status = 'SUSPENDED', reject_reason = ? WHERE merchant_id = ?").run(reason || null, m.merchant_id);
  notify(m.owner_user_id, 'merchant_suspended', `ร้าน "${m.shop_name_th}" ถูกระงับชั่วคราว${reason ? ': ' + reason : ''}`, { merchant_id: m.merchant_id });
  res.json({ status: 'SUSPENDED' });
});

router.post('/merchants/:id/unsuspend', (req, res) => {
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  if (m.approval_status !== 'SUSPENDED') return res.status(409).json({ error: 'ร้านนี้ไม่ได้ถูกระงับ' });
  db.prepare("UPDATE merchants SET approval_status = 'APPROVED', reject_reason = NULL WHERE merchant_id = ?").run(m.merchant_id);
  res.json({ status: 'APPROVED' });
});

// ---- community moderation ----------------------------------------------------------------------------------------------
router.get('/community/posts', (req, res) => {
  const reportedOnly = req.query.reported === '1';
  const rows = db.prepare(`SELECT p.post_id, p.content, p.status, p.timestamp, u.username, l.name AS location_name,
      (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.post_id) AS likes,
      (SELECT COUNT(*) FROM community_comments c WHERE c.post_id = p.post_id) AS comments,
      (SELECT COUNT(*) FROM post_images i WHERE i.post_id = p.post_id) AS images,
      (SELECT COUNT(*) FROM post_reports x WHERE x.post_id = p.post_id) AS reports
    FROM community_posts p JOIN users u ON u.user_id = p.user_id LEFT JOIN locations l ON l.location_id = p.location_id
    ${reportedOnly ? 'WHERE (SELECT COUNT(*) FROM post_reports x WHERE x.post_id = p.post_id) > 0' : ''}
    ORDER BY ${reportedOnly ? 'reports DESC,' : ''} p.timestamp DESC LIMIT 100`).all();
  res.json({ posts: rows });
});

router.get('/community/posts/:id/reports', (req, res) => {
  const rows = db.prepare(`SELECT x.reason, x.created_at, u.username AS reporter FROM post_reports x JOIN users u ON u.user_id = x.reporter_user_id
    WHERE x.post_id = ? ORDER BY x.created_at DESC`).all(req.params.id);
  res.json({ reports: rows });
});

// Picture of a post for the moderation list (admins see hidden posts too).
router.get('/community/posts/:id/images', (req, res) => {
  const rows = db.prepare('SELECT image FROM post_images WHERE post_id = ? ORDER BY position').all(req.params.id);
  res.json({ images: rows.map((r) => r.image) });
});

router.put('/community/posts/:id', (req, res) => {
  const status = (req.body || {}).status;
  if (!['visible', 'hidden'].includes(status)) return res.status(400).json({ error: 'สถานะต้องเป็น visible หรือ hidden' });
  const changed = db.prepare('UPDATE community_posts SET status = ? WHERE post_id = ?').run(status, req.params.id).changes;
  if (!changed) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  res.json({ status });
});

// How many people tapped "order physical card" for each design.
router.get('/order-intents', (req, res) => {
  const rows = db.prepare(`SELECT t.template_id, t.name, t.rarity, COUNT(i.intent_id) AS interested, SUM(i.notified_at IS NULL) AS unnotified, MAX(i.created_at) AS last_at
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
