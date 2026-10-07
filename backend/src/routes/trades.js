const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const { getCard } = require('../services/cardService');
const { notify } = require('../services/notify');
const { TRADE_TTL_MS, resolveTrade, expireTrades, completeTrade } = require('../services/tradeService');

const router = express.Router();
const MAX_PENDING_OUT = 20;

const name = (u) => (u ? `${u.first_name} ${u.last_name}`.trim() : '');

function tradeView(t) {
  const user = (id) => db.prepare('SELECT user_id, username, first_name, last_name FROM users WHERE user_id = ?').get(id);
  const from = user(t.from_user_id);
  const to = user(t.to_user_id);
  return {
    trade_id: t.trade_id,
    mode: t.mode,
    status: t.status,
    created_at: t.created_at,
    expires_at: t.expires_at,
    resolved_at: t.resolved_at,
    from: { user_id: from.user_id, username: from.username, name: name(from) },
    to: { user_id: to.user_id, username: to.username, name: name(to) },
    offered_card: getCard(t.offered_card_id),
    requested_card: t.requested_card_id ? getCard(t.requested_card_id) : null,
  };
}

// Offer a card: a gift (nothing back) or a swap for one of the recipient's cards. The offered card is locked until answered.
router.post('/', authMiddleware, (req, res) => {
  expireTrades();
  const b = req.body || {};
  if (!['gift', 'swap'].includes(b.mode)) return res.status(400).json({ error: 'เลือกรูปแบบ: ให้ฟรี (gift) หรือแลกการ์ด (swap)' });
  const target = b.to_username
    ? db.prepare('SELECT * FROM users WHERE username = ?').get(String(b.to_username))
    : db.prepare('SELECT * FROM users WHERE user_id = ?').get(String(b.to_user_id || ''));
  if (!target) return res.status(404).json({ error: 'ไม่พบผู้รับ' });
  if (target.user_id === req.user.user_id) return res.status(400).json({ error: 'ส่งการ์ดให้ตัวเองไม่ได้' });

  const offered = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(String(b.offered_card_id || ''));
  if (!offered || offered.owner_user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบการ์ดนี้ในคลังของคุณ' });
  if (offered.activation_status === 'LOCKED_IN_TRADE') return res.status(409).json({ error: 'การ์ดใบนี้อยู่ในข้อเสนอแลกเปลี่ยนอื่นอยู่แล้ว' });
  if (offered.activation_status !== 'CLAIMED') return res.status(409).json({ error: 'การ์ดใบนี้ยังไม่พร้อมแลกเปลี่ยน' });

  let requestedId = null;
  if (b.mode === 'swap') {
    const requested = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(String(b.requested_card_id || ''));
    if (!requested || requested.owner_user_id !== target.user_id) return res.status(404).json({ error: 'การ์ดที่ขอแลกไม่ได้อยู่กับผู้รับ' });
    if (requested.activation_status !== 'CLAIMED') return res.status(409).json({ error: 'การ์ดที่ขอแลกกำลังอยู่ในข้อเสนอแลกเปลี่ยนอื่น' });
    requestedId = requested.card_instance_id;
  }
  const pendingOut = db.prepare("SELECT COUNT(*) AS c FROM trades WHERE from_user_id = ? AND status = 'pending'").get(req.user.user_id).c;
  if (pendingOut >= MAX_PENDING_OUT) return res.status(429).json({ error: 'มีข้อเสนอที่ยังรอคำตอบมากเกินไป' });

  const tradeId = newId('trd');
  const now = Date.now();
  const ok = db.transaction(() => {
    const locked = db.prepare("UPDATE all_cards SET activation_status = 'LOCKED_IN_TRADE' WHERE card_instance_id = ? AND owner_user_id = ? AND activation_status = 'CLAIMED'")
      .run(offered.card_instance_id, req.user.user_id).changes;
    if (locked !== 1) return false;
    db.prepare(`INSERT INTO trades (trade_id, from_user_id, to_user_id, mode, offered_card_id, requested_card_id, status, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)`)
      .run(tradeId, req.user.user_id, target.user_id, b.mode, offered.card_instance_id, requestedId, new Date(now).toISOString(), new Date(now + TRADE_TTL_MS).toISOString());
    return true;
  })();
  if (!ok) return res.status(409).json({ error: 'การ์ดใบนี้อยู่ในข้อเสนอแลกเปลี่ยนอื่นอยู่แล้ว' });

  const card = getCard(offered.card_instance_id);
  notify(target.user_id, 'trade_offer',
    `${name(req.user)} (@${req.user.username}) ${b.mode === 'gift' ? 'ส่งการ์ดให้คุณ' : 'ขอแลกการ์ดกับคุณ'}: ${card.name} ${card.serial_label || ''}`.trim(),
    { trade_id: tradeId });
  res.status(201).json({ trade: tradeView(db.prepare('SELECT * FROM trades WHERE trade_id = ?').get(tradeId)) });
});

router.get('/', authMiddleware, (req, res) => {
  expireTrades();
  const uid = req.user.user_id;
  const rows = (sql, ...args) => db.prepare(sql).all(...args).map(tradeView);
  res.json({
    incoming: rows("SELECT * FROM trades WHERE to_user_id = ? AND status = 'pending' ORDER BY created_at DESC", uid),
    outgoing: rows("SELECT * FROM trades WHERE from_user_id = ? AND status = 'pending' ORDER BY created_at DESC", uid),
    history: rows("SELECT * FROM trades WHERE (from_user_id = ? OR to_user_id = ?) AND status != 'pending' ORDER BY resolved_at DESC LIMIT 30", uid, uid),
  });
});

function loadPending(req, res, role) {
  expireTrades();
  const t = db.prepare('SELECT * FROM trades WHERE trade_id = ?').get(req.params.id);
  const mine = t && (role === 'recipient' ? t.to_user_id : t.from_user_id) === req.user.user_id;
  if (!t || !mine) {
    res.status(404).json({ error: 'ไม่พบข้อเสนอนี้' });
    return null;
  }
  if (t.status !== 'pending') {
    res.status(409).json({ error: 'ข้อเสนอนี้ถูกดำเนินการไปแล้ว', status: t.status });
    return null;
  }
  return t;
}

router.post('/:id/accept', authMiddleware, (req, res) => {
  const t = loadPending(req, res, 'recipient');
  if (!t) return;
  const r = completeTrade(t);
  if (r.error) return res.status(409).json({ error: r.error });
  notify(t.from_user_id, 'trade_accepted', `${name(req.user)} (@${req.user.username}) ยอมรับข้อเสนอของคุณแล้ว`, { trade_id: t.trade_id });
  res.json({ trade: tradeView(db.prepare('SELECT * FROM trades WHERE trade_id = ?').get(t.trade_id)) });
});

router.post('/:id/reject', authMiddleware, (req, res) => {
  const t = loadPending(req, res, 'recipient');
  if (!t) return;
  resolveTrade(t, 'rejected');
  notify(t.from_user_id, 'trade_rejected', `${name(req.user)} (@${req.user.username}) ปฏิเสธข้อเสนอของคุณ การ์ดถูกปลดล็อกแล้ว`, { trade_id: t.trade_id });
  res.json({ status: 'rejected' });
});

router.post('/:id/cancel', authMiddleware, (req, res) => {
  const t = loadPending(req, res, 'sender');
  if (!t) return;
  resolveTrade(t, 'cancelled');
  notify(t.to_user_id, 'trade_cancelled', `${name(req.user)} (@${req.user.username}) ยกเลิกข้อเสนอแล้ว`, { trade_id: t.trade_id });
  res.json({ status: 'cancelled' });
});

module.exports = router;
module.exports.tradeView = tradeView;
