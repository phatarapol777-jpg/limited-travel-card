const db = require('../db');
const { logOwnership } = require('./cardService');
const { notify } = require('./notify');

const TRADE_TTL_MS = 48 * 60 * 60 * 1000;

/** Moves a pending trade to a final status and unlocks the offered card (if it is still locked for this trade). */
const resolveTrade = db.transaction((trade, status) => {
  db.prepare("UPDATE trades SET status = ?, resolved_at = ? WHERE trade_id = ? AND status = 'pending'").run(status, new Date().toISOString(), trade.trade_id);
  db.prepare("UPDATE all_cards SET activation_status = 'CLAIMED' WHERE card_instance_id = ? AND activation_status = 'LOCKED_IN_TRADE' AND owner_user_id = ?")
    .run(trade.offered_card_id, trade.from_user_id);
});

/** Pending trades older than 48 hours expire so their cards do not stay locked forever. */
function expireTrades() {
  const stale = db.prepare("SELECT * FROM trades WHERE status = 'pending' AND expires_at < ?").all(new Date().toISOString());
  for (const t of stale) {
    resolveTrade(t, 'expired');
    notify(t.from_user_id, 'trade_expired', 'ข้อเสนอแลกเปลี่ยนการ์ดหมดอายุแล้ว การ์ดของคุณถูกปลดล็อกกลับมาแล้ว', { trade_id: t.trade_id });
  }
  return stale.length;
}

/** Hands the offered card to the recipient (and the requested card to the sender for a swap) in one transaction. */
const completeTrade = db.transaction((trade) => {
  const offered = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(trade.offered_card_id);
  if (!offered || offered.owner_user_id !== trade.from_user_id || offered.activation_status !== 'LOCKED_IN_TRADE') {
    return { error: 'การ์ดที่เสนอไม่พร้อมแลกเปลี่ยนแล้ว' };
  }
  let requested = null;
  if (trade.mode === 'swap') {
    requested = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(trade.requested_card_id);
    if (!requested || requested.owner_user_id !== trade.to_user_id) return { error: 'การ์ดที่ขอแลกไม่ได้อยู่กับคุณแล้ว' };
    if (requested.activation_status !== 'CLAIMED') return { error: 'การ์ดที่ขอแลกกำลังอยู่ในข้อเสนอแลกเปลี่ยนอื่น' };
  }
  const now = new Date().toISOString();
  const give = db.prepare("UPDATE all_cards SET owner_user_id = ?, activation_status = 'CLAIMED', acquired_at = ? WHERE card_instance_id = ? AND owner_user_id = ?");
  if (give.run(trade.to_user_id, now, offered.card_instance_id, trade.from_user_id).changes !== 1) return { error: 'การ์ดที่เสนอไม่พร้อมแลกเปลี่ยนแล้ว' };
  logOwnership(offered.card_instance_id, trade.from_user_id, trade.to_user_id, trade.mode === 'gift' ? 'gift' : 'trade', trade.trade_id);
  if (requested) {
    if (give.run(trade.from_user_id, now, requested.card_instance_id, trade.to_user_id).changes !== 1) throw new Error('swap failed');
    logOwnership(requested.card_instance_id, trade.to_user_id, trade.from_user_id, 'trade', trade.trade_id);
  }
  db.prepare("UPDATE trades SET status = 'accepted', resolved_at = ? WHERE trade_id = ? AND status = 'pending'").run(now, trade.trade_id);
  return { ok: true };
});

module.exports = { TRADE_TTL_MS, resolveTrade, expireTrades, completeTrade };
