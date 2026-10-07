const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const { mintCard, normalizeRarity, getCard, serialLabel } = require('../services/cardService');
const Q = require('../services/questService');
const settings = require('../services/settings');
const { haversineMeters } = require('../services/kioskService');

const router = express.Router();
const MAX_PENDING_PER_USER = 10;
const MAX_MINT_LIMIT = 100000;

function optionalUserId(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const session = token ? db.prepare('SELECT user_id FROM sessions WHERE token = ?').get(token) : null;
  return session ? session.user_id : null;
}

/** The fields a client may see about a quest (never the image data: that is served by /api/media). */
function questView(q, extra = {}) {
  return {
    quest_id: q.quest_id,
    title: q.title,
    description: q.description,
    location_id: q.location_id,
    location_name: q.location_name,
    province: q.province,
    start_date: q.start_date,
    end_date: q.end_date,
    permanent: !!q.permanent,
    status: q.status,
    reject_reason: q.reject_reason,
    phase: q.status === 'approved' ? Q.questPhase(q) : null,
    created_at: q.created_at,
    has_cover: !!q.has_cover,
    card: q.template_id ? {
      template_id: q.template_id,
      name: q.card_name,
      rarity: q.rarity,
      lore: q.lore,
      mint_limit: q.mint_limit,
      minted_count: q.minted_count,
      remaining: q.mint_limit === null ? null : Math.max(0, q.mint_limit - q.minted_count),
      has_image: !!q.has_card_image,
    } : null,
    ...extra,
  };
}

const QUEST_SELECT = `SELECT q.*, (q.cover_image IS NOT NULL) AS has_cover, l.name AS location_name, l.province,
    t.name AS card_name, t.rarity, t.lore, t.mint_limit, t.minted_count, (t.image IS NOT NULL) AS has_card_image, u.username AS creator_username
  FROM quests q JOIN locations l ON l.location_id = q.location_id
  LEFT JOIN card_templates t ON t.template_id = q.template_id JOIN users u ON u.user_id = q.creator_user_id`;

/**
 * Validates a quest form. With `existing` (an edit), the images are optional: a missing image keeps the old one.
 * Returns {error} or {data}.
 */
function parseQuestForm(b, existing = null) {
  const title = String(b.title || '').trim();
  const description = String(b.description || '').trim();
  const cardName = String(b.card_name || '').trim();
  const lore = String(b.card_lore || '').trim();
  const permanent = b.permanent === true;
  if (!title || title.length > 80) return { error: 'ชื่อภารกิจต้องไม่ว่างและไม่เกิน 80 ตัวอักษร' };
  if (!description || description.length > 2000) return { error: 'กรอกคำอธิบายภารกิจ (ไม่เกิน 2,000 ตัวอักษร)' };
  if (!cardName || cardName.length > 60) return { error: 'ชื่อการ์ดต้องไม่ว่างและไม่เกิน 60 ตัวอักษร' };
  if (lore.length > 500) return { error: 'เรื่องราวการ์ดยาวเกิน 500 ตัวอักษร' };
  if (!db.prepare('SELECT 1 FROM locations WHERE location_id = ?').get(b.location_id)) return { error: 'ไม่พบสถานที่ที่เลือก' };
  const rarity = String(b.rarity || '').toLowerCase();
  if (!['normal', 'rare', 'special'].includes(rarity)) return { error: 'เลือกระดับความหายาก (Normal / Rare / Special)' };
  const limit = Number(b.mint_limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_MINT_LIMIT) return { error: `จำนวนการ์ดสูงสุดต้องเป็นจำนวนเต็ม 1 ถึง ${MAX_MINT_LIMIT}` };
  if (!permanent) {
    if (!Q.validDate(b.start_date) || !Q.validDate(b.end_date)) return { error: 'ระบุวันที่เริ่มและวันที่สิ้นสุด หรือเลือกภารกิจถาวร' };
    if (b.end_date < b.start_date) return { error: 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม' };
    if (b.end_date < Q.bangkokToday()) return { error: 'วันที่สิ้นสุดผ่านมาแล้ว' };
  }
  let cover = b.cover_image;
  let art = b.card_image;
  if (existing && (cover === undefined || cover === null || cover === '')) cover = existing.cover_image;
  else {
    const coverErr = Q.imageError(cover, Q.MAX_COVER_CHARS, 'ภาพประกอบภารกิจ');
    if (coverErr) return { error: coverErr };
  }
  if (existing && (art === undefined || art === null || art === '')) art = existing.card_image;
  else {
    const artErr = Q.imageError(art, Q.MAX_CARD_IMAGE_CHARS, 'ภาพการ์ด');
    if (artErr) return { error: artErr };
  }
  return {
    data: {
      title, description, cardName, lore, permanent, rarity, limit, cover, art,
      location_id: b.location_id, start_date: permanent ? null : b.start_date, end_date: permanent ? null : b.end_date,
    },
  };
}

// Submit a quest request (Status: pending). Any signed-in user may submit; an admin must approve it.
router.post('/', authMiddleware, (req, res) => {
  const parsed = parseQuestForm(req.body || {});
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  const d = parsed.data;
  const pending = db.prepare("SELECT COUNT(*) AS c FROM quests WHERE creator_user_id = ? AND status = 'pending'").get(req.user.user_id).c;
  if (pending >= MAX_PENDING_PER_USER) return res.status(429).json({ error: 'มีคำร้องที่รออนุมัติมากเกินไป กรุณารอให้แอดมินตรวจสอบก่อน' });

  const questId = newId('qst');
  const templateId = newId('tpl');
  const now = new Date().toISOString();
  db.transaction(() => {
    db.prepare(`INSERT INTO card_templates (template_id, location_id, mission_id, name, icon, color_hex, type, rarity, card_type, image, lore, mint_limit, minted_count, quest_id)
      VALUES (?, ?, NULL, ?, 'style', '#4C6B8A', 'quest', ?, 'QUEST_LOCATION', ?, ?, ?, 0, ?)`)
      .run(templateId, d.location_id, d.cardName, normalizeRarity(d.rarity), d.art, d.lore || null, d.limit, questId);
    db.prepare(`INSERT INTO quests (quest_id, creator_user_id, title, location_id, description, cover_image, start_date, end_date, permanent, status, template_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`)
      .run(questId, req.user.user_id, d.title, d.location_id, d.description, d.cover, d.start_date, d.end_date, d.permanent ? 1 : 0, templateId, now);
  })();
  res.status(201).json({ quest_id: questId, status: 'pending' });
});

// Fix a quest that was rejected (or is still waiting) and send it for review again. Approved quests are closed and re-created instead.
router.put('/:id', authMiddleware, (req, res) => {
  const q = db.prepare('SELECT q.*, t.image AS card_image FROM quests q LEFT JOIN card_templates t ON t.template_id = q.template_id WHERE q.quest_id = ?').get(req.params.id);
  if (!q || q.creator_user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  if (!['pending', 'rejected'].includes(q.status)) {
    return res.status(409).json({ error: 'แก้ไขได้เฉพาะภารกิจที่รออนุมัติหรือถูกปฏิเสธ ภารกิจที่อนุมัติแล้วให้ปิดแล้วสร้างใหม่' });
  }
  const parsed = parseQuestForm(req.body || {}, q);
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  const d = parsed.data;
  db.transaction(() => {
    db.prepare(`UPDATE quests SET title = ?, location_id = ?, description = ?, cover_image = ?, start_date = ?, end_date = ?, permanent = ?,
        status = 'pending', reject_reason = NULL, reviewed_at = NULL, reviewed_by = NULL WHERE quest_id = ?`)
      .run(d.title, d.location_id, d.description, d.cover, d.start_date, d.end_date, d.permanent ? 1 : 0, q.quest_id);
    db.prepare('UPDATE card_templates SET location_id = ?, name = ?, rarity = ?, image = ?, lore = ?, mint_limit = ? WHERE template_id = ?')
      .run(d.location_id, d.cardName, normalizeRarity(d.rarity), d.art, d.lore || null, d.limit, q.template_id);
  })();
  res.json({ quest_id: q.quest_id, status: 'pending' });
});

// The creator withdraws a waiting request or switches off a running quest (people who already claimed keep their cards).
router.post('/:id/close', authMiddleware, (req, res) => {
  const q = db.prepare('SELECT * FROM quests WHERE quest_id = ?').get(req.params.id);
  if (!q || q.creator_user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  if (!['pending', 'approved'].includes(q.status)) return res.status(409).json({ error: 'ภารกิจนี้ปิดหรือถูกปฏิเสธไปแล้ว' });
  db.prepare("UPDATE quests SET status = 'closed' WHERE quest_id = ?").run(q.quest_id);
  res.json({ status: 'closed' });
});

// The signed-in user's own quest requests (status, reject reason, how many cards are left).
router.get('/mine', authMiddleware, (req, res) => {
  const rows = db.prepare(`${QUEST_SELECT} WHERE q.creator_user_id = ? ORDER BY q.created_at DESC`).all(req.user.user_id);
  res.json({ quests: rows.map((q) => questView(q)) });
});

// Approved quests people can currently do (optionally at one location), with how many cards remain.
router.get('/', (req, res) => {
  const userId = optionalUserId(req);
  const rows = db.prepare(`${QUEST_SELECT} WHERE q.status = 'approved' ${req.query.location_id ? 'AND q.location_id = ?' : ''} ORDER BY q.created_at DESC`)
    .all(...(req.query.location_id ? [req.query.location_id] : []));
  const claimed = userId ? new Set(db.prepare('SELECT quest_id FROM quest_claims WHERE user_id = ?').all(userId).map((r) => r.quest_id)) : new Set();
  const quests = rows.filter((q) => Q.questPhase(q) !== 'ended').map((q) => questView(q, { claimed_by_me: claimed.has(q.quest_id) }));
  res.json({ quests });
});

// Pending images are private: only the creator and admins can load them (approved ones are public via /api/media).
router.get('/:id/images', authMiddleware, (req, res) => {
  const q = db.prepare('SELECT q.*, t.image AS card_image FROM quests q LEFT JOIN card_templates t ON t.template_id = q.template_id WHERE q.quest_id = ?').get(req.params.id);
  if (!q || (q.creator_user_id !== req.user.user_id && !req.user.is_admin)) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  res.json({ cover_image: q.cover_image, card_image: q.card_image });
});

// The printable QR payload, available to the creator once an admin has approved the quest.
router.get('/:id/qr', authMiddleware, (req, res) => {
  const q = db.prepare('SELECT * FROM quests WHERE quest_id = ?').get(req.params.id);
  if (!q || q.creator_user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบภารกิจ' });
  if (q.status !== 'approved') return res.status(409).json({ error: 'ภารกิจยังไม่ได้รับอนุมัติ จึงยังไม่มี QR Code' });
  res.json({ quest_id: q.quest_id, payload: Q.questPayload(q.quest_id), title: q.title });
});

// Claim the reward by scanning the quest's QR at the place.
router.post('/claim', authMiddleware, (req, res) => {
  const questId = Q.parseQuestPayload((req.body || {}).payload);
  if (!questId) return res.status(400).json({ error: 'QR Code ภารกิจไม่ถูกต้อง' });
  const quest = db.prepare(`${QUEST_SELECT} WHERE q.quest_id = ?`).get(questId);
  if (!quest) return res.status(404).json({ error: 'ไม่พบภารกิจนี้' });
  if (quest.status === 'pending') return res.status(409).json({ error: 'ภารกิจนี้ยังรอการอนุมัติจากแอดมิน' });
  if (quest.status !== 'approved') return res.status(409).json({ error: 'ภารกิจนี้ปิดแล้ว' });
  const phase = Q.questPhase(quest);
  if (phase === 'upcoming') return res.status(409).json({ error: `ภารกิจนี้จะเริ่มวันที่ ${quest.start_date}` });
  if (phase === 'ended') return res.status(409).json({ error: 'ภารกิจนี้หมดเวลาแล้ว' });

  // The QR is printed and fixed, so a photo of it works from anywhere: also require the phone to be near the place.
  if (settings.get('quest_geo_check')) {
    const { lat, lng } = req.body || {};
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return res.status(400).json({ code: 'location_required', error: 'ต้องเปิดตำแหน่ง (GPS) บนมือถือเพื่อรับการ์ดภารกิจ กรุณาอนุญาตการเข้าถึงตำแหน่งแล้วสแกนอีกครั้ง' });
    }
    const place = db.prepare('SELECT latitude, longitude FROM locations WHERE location_id = ?').get(quest.location_id);
    const distance = Math.round(haversineMeters(lat, lng, place.latitude, place.longitude));
    const radius = settings.get('quest_geo_radius_m');
    if (distance > radius) {
      return res.status(403).json({ code: 'too_far', error: `คุณอยู่ห่างจากสถานที่ภารกิจประมาณ ${distance.toLocaleString('en-US')} เมตร (ต้องอยู่ภายใน ${radius.toLocaleString('en-US')} เมตร)` });
    }
  }

  const result = db.transaction(() => {
    if (db.prepare('SELECT 1 FROM quest_claims WHERE quest_id = ? AND user_id = ?').get(questId, req.user.user_id)) return { error: 'duplicate' };
    const minted = mintCard({ templateId: quest.template_id, userId: req.user.user_id, questCompletionId: questId, reason: 'quest' });
    if (!minted.ok) return { error: minted.reason };
    db.prepare('INSERT INTO quest_claims (quest_id, user_id, card_instance_id, claimed_at) VALUES (?, ?, ?, ?)')
      .run(questId, req.user.user_id, minted.cardId, new Date().toISOString());
    return { cardId: minted.cardId };
  })();
  if (result.error === 'duplicate') return res.status(409).json({ error: 'คุณรับการ์ดจากภารกิจนี้ไปแล้ว' });
  if (result.error === 'sold_out') return res.status(409).json({ error: 'การ์ดของภารกิจนี้แจกครบจำนวนแล้ว' });
  if (result.error) return res.status(409).json({ error: 'รับการ์ดไม่สำเร็จ' });
  res.status(201).json({ card: getCard(result.cardId), quest: questView(quest) });
});

module.exports = router;
module.exports.questView = questView;
module.exports.QUEST_SELECT = QUEST_SELECT;
module.exports.serialLabel = serialLabel;
