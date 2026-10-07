const crypto = require('crypto');
const db = require('../db');
const { hashPassword } = require('../util');
const { resolveTrade } = require('./tradeService');
const { notify } = require('./notify');

/**
 * Deletes a traveler's account by anonymising it. Rows elsewhere (cards, history, audit log) point at the user id, so the
 * row stays but holds no personal data any more: no name, email, phone, face data, Google id or password.
 * Pending trades in both directions are cancelled (the other side is told) and their cards are unlocked.
 */
const deleteAccount = db.transaction((userId) => {
  const user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(userId);
  if (!user || user.is_admin) return false;

  for (const t of db.prepare("SELECT * FROM trades WHERE status = 'pending' AND (from_user_id = ? OR to_user_id = ?)").all(userId, userId)) {
    resolveTrade(t, 'cancelled');
    const other = t.from_user_id === userId ? t.to_user_id : t.from_user_id;
    notify(other, 'trade_cancelled', 'ข้อเสนอแลกเปลี่ยนถูกยกเลิก เพราะอีกฝ่ายลบบัญชีแล้ว', { trade_id: t.trade_id });
  }
  db.prepare('DELETE FROM user_pins WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM sessions WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM notifications WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM physical_order_intents WHERE user_id = ?').run(userId);
  db.prepare("UPDATE quests SET status = 'closed' WHERE creator_user_id = ? AND status IN ('pending', 'approved')").run(userId);
  db.prepare("UPDATE community_posts SET status = 'hidden' WHERE user_id = ?").run(userId);
  db.prepare('DELETE FROM post_images WHERE post_id IN (SELECT post_id FROM community_posts WHERE user_id = ?)').run(userId);
  db.prepare('DELETE FROM community_comments WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM post_reactions WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM post_reports WHERE reporter_user_id = ?').run(userId);
  db.prepare('DELETE FROM follows WHERE follower_user_id = ? OR following_user_id = ?').run(userId, userId);
  db.prepare('DELETE FROM user_badges WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM checkin_monthly_stats WHERE user_id = ?').run(userId);
  if (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'merchants'").get()) {
    db.prepare("UPDATE merchants SET approval_status = 'SUSPENDED' WHERE owner_user_id = ? AND approval_status != 'REJECTED'").run(userId);
  }

  const tag = crypto.randomBytes(5).toString('hex');
  const { hash, salt } = hashPassword(crypto.randomBytes(32).toString('hex')); // nobody knows this password
  db.prepare(`UPDATE users SET username = ?, first_name = 'ผู้ใช้ที่ลบบัญชี', last_name = '-', email = ?, phone = NULL,
      password_hash = ?, password_salt = ?, display_name = NULL, avatar = NULL, cover = NULL, bio = NULL, selected_badge_id = NULL, face_photo = NULL, face_descriptor = NULL, face_data = NULL, google_sub = NULL
    WHERE user_id = ?`).run(`deleted-${tag}`, `deleted-${tag}@invalid.local`, hash, salt, userId);
  return true;
});

module.exports = { deleteAccount };
