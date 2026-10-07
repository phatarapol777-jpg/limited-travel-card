const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const { CARD_SELECT, cardView, getCard, logOwnership } = require('../services/cardService');

const router = express.Router();

router.get('/', authMiddleware, (req, res) => {
  const cards = db.prepare(`${CARD_SELECT} WHERE c.owner_user_id = ? AND c.activation_status != 'VOIDED' ORDER BY c.acquired_at DESC`).all(req.user.user_id).map(cardView);
  res.json({ cards });
});

// Activate a physical card by scanning the unique QR on its back. The first scan binds it to the scanner for good.
const activationFailures = new Map(); // user_id -> recent failed attempts (the codes are 128-bit, this just stops hammering)
const ACTIVATION_WINDOW_MS = 10 * 60 * 1000;
const ACTIVATION_MAX_FAILURES = 20;

router.post('/activate', authMiddleware, (req, res) => {
  const now = Date.now();
  const failures = (activationFailures.get(req.user.user_id) || []).filter((t) => now - t < ACTIVATION_WINDOW_MS);
  if (failures.length >= ACTIVATION_MAX_FAILURES) return res.status(429).json({ error: 'ลองสแกนผิดบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่' });
  const fail = (status, body) => {
    failures.push(now);
    activationFailures.set(req.user.user_id, failures);
    return res.status(status).json(body);
  };

  const payload = (req.body || {}).payload;
  const parts = typeof payload === 'string' && payload.length <= 100 ? payload.split('|') : [];
  if (parts.length !== 2 || parts[0] !== 'TRVCARD' || !/^[a-f0-9]{32}$/.test(parts[1])) {
    return fail(400, { error: 'QR Code การ์ดไม่ถูกต้อง' });
  }
  const card = db.prepare('SELECT * FROM all_cards WHERE activation_code = ?').get(parts[1]);
  if (!card) return fail(404, { error: 'ไม่พบการ์ดใบนี้ในระบบ' });

  const claimedMessage = () => {
    const owner = card.owner_user_id ? db.prepare('SELECT username FROM users WHERE user_id = ?').get(card.owner_user_id) : null;
    // the card may have changed hands since it was activated: report who activated it first, from the ownership log
    const first = db.prepare("SELECT l.to_user_id, l.created_at, u.username FROM card_ownership_log l JOIN users u ON u.user_id = l.to_user_id WHERE l.card_instance_id = ? AND l.reason = 'activation' ORDER BY l.created_at LIMIT 1").get(card.card_instance_id);
    const who = (first && first.username) || (owner && owner.username) || 'ผู้ใช้อื่น';
    const when = (first && first.created_at) || card.claimed_at || '';
    return { error: `การ์ดใบนี้ถูกเปิดใช้งานไปแล้วโดยผู้ใช้ ${who} เมื่อวันที่ ${when}`, claimed_by: who, claimed_at: when };
  };
  if (card.activation_status === 'VOIDED') {
    return res.status(409).json({ code: 'voided', error: 'การ์ดใบนี้ถูกยกเลิกโดยผู้ดูแลระบบ ไม่สามารถเปิดใช้งานได้' });
  }
  if (card.activation_status !== 'UNCLAIMED' || card.owner_user_id) {
    return res.status(409).json(claimedMessage());
  }
  const claimedNow = new Date().toISOString();
  const changes = db.transaction(() => {
    const r = db.prepare(`UPDATE all_cards SET owner_user_id = ?, activation_status = 'CLAIMED', claimed_at = ?, acquired_at = ?
      WHERE card_instance_id = ? AND owner_user_id IS NULL AND activation_status = 'UNCLAIMED'`)
      .run(req.user.user_id, claimedNow, claimedNow, card.card_instance_id).changes;
    if (r === 1) logOwnership(card.card_instance_id, null, req.user.user_id, 'activation');
    return r;
  })();
  if (changes !== 1) {
    const fresh = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(card.card_instance_id);
    Object.assign(card, fresh);
    return res.status(409).json(claimedMessage());
  }
  res.status(201).json({ card: getCard(card.card_instance_id) });
});

// "Order physical card": only records interest (demand check). No payment, no shipping address.
router.post('/:id/order-intent', authMiddleware, (req, res) => {
  const card = db.prepare('SELECT c.*, t.name FROM all_cards c JOIN card_templates t ON t.template_id = c.template_id WHERE c.card_instance_id = ?').get(req.params.id);
  if (!card || card.owner_user_id !== req.user.user_id || card.activation_status === 'VOIDED') return res.status(404).json({ error: 'ไม่พบการ์ดใบนี้ในคลังของคุณ' });
  if (card.card_type !== 'QUEST_LOCATION') return res.status(400).json({ error: 'การ์ดชนิดนี้เป็นการ์ดจริงอยู่แล้ว สั่งซื้อได้เฉพาะการ์ดภารกิจ/สถานที่' });
  const existing = db.prepare('SELECT 1 FROM physical_order_intents WHERE user_id = ? AND template_id = ?').get(req.user.user_id, card.template_id);
  if (!existing) {
    db.prepare('INSERT INTO physical_order_intents (intent_id, user_id, template_id, card_instance_id, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(newId('int'), req.user.user_id, card.template_id, card.card_instance_id, new Date().toISOString());
  }
  res.status(existing ? 200 : 201).json({
    registered: true,
    already_registered: !!existing,
    message: 'เปิดรับความสนใจสั่งซื้อการ์ดจริงแล้ว ระบบจะแจ้งเตือนเมื่อสินค้าพร้อมจัดส่ง',
  });
});

module.exports = router;
