const express = require('express');
const db = require('../db');
const { newId, authMiddleware, SESSION_MAX_AGE_MS } = require('../util');
const { bangkokToday } = require('../services/questService');
const M = require('../services/merchantService');

const router = express.Router();

function optionalUser(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const session = token ? db.prepare('SELECT user_id, created_at FROM sessions WHERE token = ?').get(token) : null;
  const fresh = session && Date.now() - new Date(session.created_at).getTime() <= SESSION_MAX_AGE_MS;
  return fresh ? db.prepare('SELECT user_id, is_admin FROM users WHERE user_id = ?').get(session.user_id) : null;
}

function privilegesOf(merchantId) {
  return db.prepare(`SELECT p.privilege_id, p.template_id, p.description, p.start_date, p.end_date,
      t.name AS card_name, t.rarity AS card_rarity, t.card_type, (t.image IS NOT NULL) AS card_has_image
    FROM merchant_privileges p JOIN card_templates t ON t.template_id = p.template_id WHERE p.merchant_id = ? ORDER BY p.rowid`).all(merchantId);
}

function privilegeView(p, today = bangkokToday()) {
  return {
    privilege_id: p.privilege_id,
    template_id: p.template_id,
    description: p.description,
    start_date: p.start_date,
    end_date: p.end_date,
    valid_now: M.privilegeValid(p, today),
    card: { template_id: p.template_id, name: p.card_name, rarity: p.card_rarity, card_type: p.card_type, has_image: !!p.card_has_image },
  };
}

/** Full detail of a shop for the app (images are referenced by id and served by /api/media). */
function detailView(m, now = Date.now()) {
  const hours = JSON.parse(m.opening_hours);
  const today = bangkokToday(now);
  const nearby = m.nearby_location_id ? db.prepare('SELECT location_id, name, province FROM locations WHERE location_id = ?').get(m.nearby_location_id) : null;
  return {
    merchant: {
      merchant_id: m.merchant_id,
      shop_name_th: m.shop_name_th,
      shop_name_en: m.shop_name_en,
      category: m.category,
      description: m.description,
      address_detail: m.address_detail,
      latitude: m.latitude,
      longitude: m.longitude,
      nearby_location: nearby,
      opening_hours: hours,
      today_hours: M.todayHoursText(hours, now),
      open_now: M.isOpenNow(hours, now),
      phone: m.phone,
      facebook: m.facebook,
      instagram: m.instagram,
      line: m.line,
      has_cover: !!m.cover_image,
      rev: m.updated_at,
      status: m.approval_status,
    },
    gallery: db.prepare('SELECT image_id FROM merchant_gallery WHERE merchant_id = ? ORDER BY position').all(m.merchant_id),
    items: db.prepare('SELECT item_id, name, price, is_signature FROM merchant_items WHERE merchant_id = ? ORDER BY position').all(m.merchant_id).map((i) => ({ ...i, is_signature: !!i.is_signature })),
    privileges: privilegesOf(m.merchant_id).filter((p) => !p.end_date || p.end_date >= today).map((p) => privilegeView(p, today)),
  };
}

// The cards a perk can be attached to (names only, never pictures or codes).
router.get('/card-picker', authMiddleware, (req, res) => {
  const ids = M.publicTemplateIds();
  const rows = db.prepare(`SELECT t.template_id, t.name, t.rarity, t.card_type, l.name AS location_name FROM card_templates t
    LEFT JOIN locations l ON l.location_id = t.location_id ORDER BY t.name`).all().filter((r) => ids.has(r.template_id));
  res.json({ cards: rows });
});

// Shops that give a perk for this card, for the "partners offering perks" section of the card page. The app sorts by distance
// on the phone, so the traveler's position never goes to the server.
router.get('/for-card/:templateId', (req, res) => {
  const today = bangkokToday();
  const rows = db.prepare(`SELECT ${M.PUBLIC_COLUMNS}, p.description AS perk, p.start_date, p.end_date FROM merchant_privileges p
    JOIN merchants m ON m.merchant_id = p.merchant_id WHERE p.template_id = ? AND m.approval_status = 'APPROVED'
    AND (p.end_date IS NULL OR p.end_date >= ?) ORDER BY m.shop_name_th`).all(req.params.templateId, today);
  res.json({
    shops: rows.map((r) => ({
      ...M.lightView(r, [r]),
      privilege: { description: r.perk, start_date: r.start_date, end_date: r.end_date, valid_now: M.privilegeValid(r, today) },
    })),
  });
});

// Every approved shop, for the map pins.
router.get('/', (req, res) => {
  const category = M.CATEGORIES.includes(req.query.category) ? req.query.category : null;
  const rows = db.prepare(`SELECT ${M.PUBLIC_COLUMNS} FROM merchants m WHERE m.approval_status = 'APPROVED' ${category ? 'AND m.category = ?' : ''} ORDER BY m.shop_name_th`)
    .all(...(category ? [category] : []));
  const perks = db.prepare('SELECT merchant_id, start_date, end_date FROM merchant_privileges').all();
  const byShop = new Map();
  for (const p of perks) byShop.set(p.merchant_id, [...(byShop.get(p.merchant_id) || []), p]);
  res.json({ shops: rows.map((r) => M.lightView(r, byShop.get(r.merchant_id) || [])) });
});

router.get('/mine', authMiddleware, (req, res) => {
  const rows = db.prepare('SELECT * FROM merchants WHERE owner_user_id = ? ORDER BY created_at DESC').all(req.user.user_id);
  res.json({
    shops: rows.map((m) => ({
      merchant_id: m.merchant_id,
      shop_name_th: m.shop_name_th,
      shop_name_en: m.shop_name_en,
      category: m.category,
      status: m.approval_status,
      reject_reason: m.reject_reason,
      has_pending_revision: !!m.pending_revision,
      revision_note: m.revision_note,
      has_cover: !!m.cover_image,
      rev: m.updated_at,
    })),
  });
});

// The owner (or an admin) loads the shop as an editable form: the waiting revision if there is one, otherwise the live content.
router.get('/:id/form', authMiddleware, (req, res) => {
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m || (m.owner_user_id !== req.user.user_id && !req.user.is_admin)) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  res.json({
    status: m.approval_status,
    reject_reason: m.reject_reason,
    revision_note: m.revision_note,
    has_pending_revision: !!m.pending_revision,
    form: M.currentForm(m.merchant_id),
  });
});

router.get('/:id', (req, res) => {
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  const viewer = optionalUser(req);
  const mayLook = m && (m.approval_status === 'APPROVED' || (viewer && (viewer.is_admin || viewer.user_id === m.owner_user_id)));
  if (!mayLook) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  res.json(detailView(m));
});

router.post('/', authMiddleware, (req, res) => {
  const parsed = M.parseMerchantForm(req.body || {});
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  const mine = db.prepare('SELECT approval_status FROM merchants WHERE owner_user_id = ?').all(req.user.user_id);
  if (mine.length >= M.MAX_SHOPS_PER_USER) return res.status(429).json({ error: `สร้างร้านได้สูงสุด ${M.MAX_SHOPS_PER_USER} ร้านต่อบัญชี` });
  if (mine.filter((x) => x.approval_status === 'PENDING').length >= M.MAX_PENDING_PER_USER) return res.status(429).json({ error: 'มีคำร้องที่รออนุมัติมากเกินไป กรุณารอให้แอดมินตรวจสอบก่อน' });

  const f = parsed.form;
  const id = newId('mrc');
  const now = new Date().toISOString();
  db.transaction(() => {
    db.prepare(`INSERT INTO merchants (merchant_id, owner_user_id, shop_name_th, shop_name_en, category, description, address_detail, latitude, longitude,
        opening_hours, approval_status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '{}', 'PENDING', ?, ?)`)
      .run(id, req.user.user_id, f.shop_name_th, f.shop_name_en, f.category, f.description, f.address_detail, f.latitude, f.longitude, now, now);
    M.applyForm(id, f);
  })();
  res.status(201).json({ merchant_id: id, status: 'PENDING' });
});

// Edit a shop. A shop that was never approved is edited directly and goes back to review. A live (approved) shop keeps showing
// its current content while the change waits for approval as a revision, so it does not vanish from the map during review.
router.put('/:id', authMiddleware, (req, res) => {
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m || m.owner_user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  if (m.approval_status === 'SUSPENDED') return res.status(409).json({ error: 'ร้านนี้ถูกระงับ กรุณาติดต่อผู้ดูแลระบบ' });
  const parsed = M.parseMerchantForm(req.body || {});
  if (parsed.error) return res.status(400).json({ error: parsed.error });

  if (m.approval_status === 'APPROVED') {
    db.prepare('UPDATE merchants SET pending_revision = ?, revision_note = NULL WHERE merchant_id = ?').run(JSON.stringify(parsed.form), m.merchant_id);
    return res.json({ merchant_id: m.merchant_id, status: 'APPROVED', revision_pending: true });
  }
  db.transaction(() => {
    M.applyForm(m.merchant_id, parsed.form);
    db.prepare("UPDATE merchants SET approval_status = 'PENDING', reject_reason = NULL, reviewed_at = NULL, reviewed_by = NULL WHERE merchant_id = ?").run(m.merchant_id);
  })();
  res.json({ merchant_id: m.merchant_id, status: 'PENDING', revision_pending: false });
});

// Withdraw a request that was never approved.
router.delete('/:id', authMiddleware, (req, res) => {
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(req.params.id);
  if (!m || m.owner_user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบร้านค้า' });
  if (!['PENDING', 'REJECTED'].includes(m.approval_status)) return res.status(409).json({ error: 'ร้านที่เปิดให้ใช้งานแล้วลบเองไม่ได้ กรุณาติดต่อผู้ดูแลระบบ' });
  db.transaction(() => {
    db.prepare('DELETE FROM merchant_gallery WHERE merchant_id = ?').run(m.merchant_id);
    db.prepare('DELETE FROM merchant_items WHERE merchant_id = ?').run(m.merchant_id);
    db.prepare('DELETE FROM merchant_privileges WHERE merchant_id = ?').run(m.merchant_id);
    db.prepare('DELETE FROM merchants WHERE merchant_id = ?').run(m.merchant_id);
  })();
  res.json({ status: 'deleted' });
});

module.exports = router;
module.exports.detailView = detailView;
