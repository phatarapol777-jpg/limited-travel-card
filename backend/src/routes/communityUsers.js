const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');
const { imageProblem } = require('../services/merchantService');
const C = require('../services/communityService');
const board = require('../services/leaderboard');

const router = express.Router();
const { LIMITS } = C;

const badgesOf = (userId) => db.prepare('SELECT badge_id, icon, title, rank_position AS rank, awarded_month AS month FROM user_badges WHERE user_id = ? ORDER BY awarded_month DESC').all(userId);

function publicUser(username) {
  return db.prepare("SELECT * FROM users WHERE username = ? AND is_admin = 0 AND username NOT LIKE 'deleted-%'").get(username);
}

function profileView(user, viewerId) {
  const author = C.authorView(user.user_id);
  const following = viewerId ? !!db.prepare('SELECT 1 FROM follows WHERE follower_user_id = ? AND following_user_id = ?').get(viewerId, user.user_id) : false;
  return {
    ...author,
    bio: user.bio || '',
    has_cover: !!user.cover,
    stats: C.communityStats(user.user_id),
    badges: badgesOf(user.user_id),
    is_following: following,
    is_me: viewerId === user.user_id,
    is_badge_visible: !!user.is_badge_visible,
    selected_badge_id: user.selected_badge_id || null,
  };
}

// My own profile, with everything the edit screen needs (including the badges I can choose from).
router.get('/me', authMiddleware, (req, res) => {
  board.finalizePastMonths();
  const user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(req.user.user_id);
  res.json({ profile: profileView(user, req.user.user_id) });
});

router.put('/me', authMiddleware, (req, res) => {
  const b = req.body || {};
  const user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(req.user.user_id);
  const set = {};

  if (b.display_name !== undefined) {
    const name = String(b.display_name || '').trim();
    if (name.length > LIMITS.MAX_DISPLAY_NAME) return res.status(400).json({ error: `ชื่อที่แสดงยาวเกินไป (ไม่เกิน ${LIMITS.MAX_DISPLAY_NAME} ตัวอักษร)` });
    set.display_name = name || null; // empty falls back to the username
  }
  if (b.bio !== undefined) {
    const bio = String(b.bio || '').trim();
    if (bio.length > LIMITS.MAX_BIO) return res.status(400).json({ error: `คำอธิบายตัวเองยาวเกินไป (ไม่เกิน ${LIMITS.MAX_BIO} ตัวอักษร)` });
    set.bio = bio || null;
  }
  for (const [key, max, label] of [['avatar', LIMITS.AVATAR_CHARS, 'รูปโปรไฟล์'], ['cover', LIMITS.COVER_CHARS, 'ภาพปก']]) {
    if (b[key] === undefined) continue;
    if (b[key] === null) {
      set[key] = null;
      continue;
    }
    const err = imageProblem(b[key], max, label);
    if (err) return res.status(400).json({ error: err });
    if (C.dbIsFull()) return res.status(507).json({ error: 'พื้นที่เก็บรูปภาพของระบบเต็มชั่วคราว' });
    set[key] = b[key];
  }
  if (b.is_badge_visible !== undefined) {
    if (typeof b.is_badge_visible !== 'boolean') return res.status(400).json({ error: 'is_badge_visible ต้องเป็น true หรือ false' });
    set.is_badge_visible = b.is_badge_visible ? 1 : 0;
  }
  if (b.selected_badge_id !== undefined) {
    if (b.selected_badge_id !== null && !db.prepare('SELECT 1 FROM user_badges WHERE badge_id = ? AND user_id = ?').get(b.selected_badge_id, req.user.user_id)) {
      return res.status(400).json({ error: 'เลือกได้เฉพาะตราสัญลักษณ์ที่คุณได้รับ' });
    }
    set.selected_badge_id = b.selected_badge_id;
  }
  const keys = Object.keys(set);
  if (keys.length) {
    const picture = 'avatar' in set || 'cover' in set;
    db.prepare(`UPDATE users SET ${keys.map((k) => `${k} = ?`).join(', ')}${picture ? ', profile_rev = profile_rev + 1' : ''} WHERE user_id = ?`).run(...keys.map((k) => set[k]), req.user.user_id);
  }
  res.json({ profile: profileView(db.prepare('SELECT * FROM users WHERE user_id = ?').get(req.user.user_id), req.user.user_id) });
});

router.get('/users/:username', (req, res) => {
  const user = publicUser(req.params.username);
  if (!user) return res.status(404).json({ error: 'ไม่พบผู้ใช้' });
  res.json({ profile: profileView(user, C.optionalUserId(req)) });
});

router.post('/users/:username/follow', authMiddleware, (req, res) => {
  const target = publicUser(req.params.username);
  if (!target) return res.status(404).json({ error: 'ไม่พบผู้ใช้' });
  if (target.user_id === req.user.user_id) return res.status(400).json({ error: 'ติดตามตัวเองไม่ได้' });
  const added = db.prepare('INSERT OR IGNORE INTO follows (follower_user_id, following_user_id, created_at) VALUES (?, ?, ?)').run(req.user.user_id, target.user_id, new Date().toISOString()).changes;
  if (added) {
    const me = C.authorView(req.user.user_id);
    C.notifyOnce(target.user_id, 'community_follow', `${me.display_name} เริ่มติดตามคุณ`, { follower: req.user.user_id, username: me.username });
  }
  res.json({ is_following: true, followers: C.communityStats(target.user_id).followers });
});

router.delete('/users/:username/follow', authMiddleware, (req, res) => {
  const target = publicUser(req.params.username);
  if (!target) return res.status(404).json({ error: 'ไม่พบผู้ใช้' });
  db.prepare('DELETE FROM follows WHERE follower_user_id = ? AND following_user_id = ?').run(req.user.user_id, target.user_id);
  res.json({ is_following: false, followers: C.communityStats(target.user_id).followers });
});

function peopleList(req, res, mine, theirs) {
  const user = publicUser(req.params.username);
  if (!user) return res.status(404).json({ error: 'ไม่พบผู้ใช้' });
  const ids = db.prepare(`SELECT ${mine} AS id FROM follows f JOIN users u ON u.user_id = f.${mine} WHERE f.${theirs} = ? AND u.username NOT LIKE 'deleted-%'
    ORDER BY f.created_at DESC LIMIT 100`).all(user.user_id).map((r) => r.id);
  const authors = C.authorViews(ids);
  res.json({ users: ids.map((id) => authors.get(id)) });
}
router.get('/users/:username/followers', (req, res) => peopleList(req, res, 'follower_user_id', 'following_user_id'));
router.get('/users/:username/following', (req, res) => peopleList(req, res, 'following_user_id', 'follower_user_id'));

router.get('/leaderboard', (req, res) => {
  const months = board.availableMonths();
  const month = months.includes(req.query.month) ? req.query.month : months[0];
  const result = board.leaderboard(month);
  const viewerId = C.optionalUserId(req);
  const mine = viewerId ? result.rows.find((r) => r.user_id === viewerId) : null;
  res.json({
    month: result.month,
    label: result.label,
    finalized: result.finalized,
    months: months.map((m) => ({ month: m, label: C.monthLabel(m) })),
    rows: result.rows.map(({ user_id, ...row }) => ({ ...row, is_me: user_id === viewerId })),
    my_rank: mine ? mine.rank : null,
  });
});

module.exports = router;
