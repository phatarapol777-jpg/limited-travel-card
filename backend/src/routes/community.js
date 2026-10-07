const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const { notify } = require('../services/notify');
const { imageProblem } = require('../services/merchantService');
const C = require('../services/communityService');

const router = express.Router();
const { LIMITS } = C;

const PAGE = 20;
const isVisible = (id) => !!db.prepare("SELECT 1 FROM community_posts WHERE post_id = ? AND status = 'visible'").get(id);
const displayOf = (userId) => (C.authorView(userId) || {}).display_name || 'ผู้ใช้';
const clip = (text, n = 40) => (text.length > n ? `${text.slice(0, n)}…` : text);

// ---- feed ---------------------------------------------------------------------------------------------------------------------
// tab=all|following|trending. Filters: tag, user (username), location, q (text). Newest first with a cursor ("before"), trending by offset.
router.get('/posts', (req, res) => {
  const viewerId = C.optionalUserId(req);
  const tab = ['all', 'following', 'trending'].includes(req.query.tab) ? req.query.tab : 'all';
  if (tab === 'following' && !viewerId) return res.status(401).json({ error: 'กรุณาเข้าสู่ระบบเพื่อดูฟีดของคนที่ติดตาม' });
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || PAGE, 1), 50);

  const where = ["p.status = 'visible'"];
  const args = [];
  if (tab === 'following') {
    where.push('p.user_id IN (SELECT following_user_id FROM follows WHERE follower_user_id = ?)');
    args.push(viewerId);
  }
  if (req.query.tag) {
    where.push('p.post_id IN (SELECT post_id FROM post_hashtags WHERE tag = ?)');
    args.push(String(req.query.tag).replace(/^#/, '').toLowerCase());
  }
  if (req.query.user) {
    where.push('p.user_id = (SELECT user_id FROM users WHERE username = ?)');
    args.push(String(req.query.user));
  }
  if (req.query.location) {
    where.push('p.location_id = ?');
    args.push(String(req.query.location));
  }
  if (req.query.q) {
    where.push("p.content LIKE ? ESCAPE '\\'");
    args.push(`%${C.escapeLike(String(req.query.q).slice(0, 60))}%`);
  }

  let rows;
  let next = null;
  if (tab === 'trending') {
    const offset = Math.min(Math.max(parseInt(req.query.offset, 10) || 0, 0), 200);
    const since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();
    rows = db.prepare(`SELECT p.*, (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.post_id AND r.created_at >= ?)
        + 2 * (SELECT COUNT(*) FROM community_comments c WHERE c.post_id = p.post_id AND c.timestamp >= ?) AS score
      FROM community_posts p WHERE ${where.join(' AND ')} AND p.timestamp >= ? ORDER BY score DESC, p.timestamp DESC, p.post_id DESC LIMIT ? OFFSET ?`)
      .all(since, since, ...args, since, limit + 1, offset);
    if (rows.length > limit) {
      rows = rows.slice(0, limit);
      next = String(offset + limit);
    }
  } else {
    const before = String(req.query.before || '');
    if (before.includes('|')) {
      const [ts, id] = before.split('|');
      where.push('(p.timestamp < ? OR (p.timestamp = ? AND p.post_id < ?))');
      args.push(ts, ts, id);
    }
    rows = db.prepare(`SELECT p.* FROM community_posts p WHERE ${where.join(' AND ')} ORDER BY p.timestamp DESC, p.post_id DESC LIMIT ?`).all(...args, limit + 1);
    if (rows.length > limit) {
      rows = rows.slice(0, limit);
      next = `${rows[rows.length - 1].timestamp}|${rows[rows.length - 1].post_id}`;
    }
  }
  res.json({ posts: C.postViews(rows, viewerId), next });
});

router.get('/posts/:id', (req, res) => {
  const row = db.prepare("SELECT * FROM community_posts WHERE post_id = ? AND status = 'visible'").get(req.params.id);
  if (!row) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  res.json({ post: C.postViews([row], C.optionalUserId(req))[0] });
});

// ---- write posts ---------------------------------------------------------------------------------------------------------------
function parsePostBody(b, { existingImageIds = null } = {}) {
  const content = typeof b.content === 'string' ? b.content.trim() : '';
  if (content.length > LIMITS.MAX_POST_TEXT) return { error: `ข้อความยาวเกินไป (ไม่เกิน ${LIMITS.MAX_POST_TEXT} ตัวอักษร)` };
  const imagesIn = Array.isArray(b.images) ? b.images : [];
  if (imagesIn.length > LIMITS.MAX_POST_IMAGES) return { error: `แนบรูปได้สูงสุด ${LIMITS.MAX_POST_IMAGES} รูปต่อโพสต์` };
  const images = []; // { image_id } (kept) or { image } (new)
  for (const it of imagesIn) {
    if (it && typeof it.image_id === 'string' && existingImageIds) {
      if (!existingImageIds.has(it.image_id)) return { error: 'ไม่พบรูปที่ต้องการเก็บไว้' };
      images.push({ image_id: it.image_id });
      continue;
    }
    const err = imageProblem(it && it.image, LIMITS.POST_IMAGE_CHARS, 'รูปภาพ');
    if (err) return { error: err };
    images.push({ image: it.image });
  }
  if (!content && !images.length) return { error: 'เขียนข้อความหรือแนบรูปอย่างน้อยหนึ่งอย่าง' };
  let locationId = null;
  if (b.location_id) {
    if (!db.prepare('SELECT 1 FROM locations WHERE location_id = ?').get(b.location_id)) return { error: 'ไม่พบสถานที่ท่องเที่ยวที่แท็ก' };
    locationId = b.location_id;
  }
  return { content, images, locationId };
}

router.post('/posts', authMiddleware, (req, res) => {
  const parsed = parsePostBody(req.body || {});
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  if (C.recentCount('community_posts', 'user_id', 'timestamp', req.user.user_id) >= LIMITS.POSTS_PER_DAY) {
    return res.status(429).json({ error: `โพสต์ได้สูงสุด ${LIMITS.POSTS_PER_DAY} โพสต์ใน 24 ชั่วโมง` });
  }
  if (parsed.images.length && C.dbIsFull()) return res.status(507).json({ error: 'พื้นที่เก็บรูปภาพของระบบเต็มชั่วคราว โพสต์ได้เฉพาะข้อความ' });

  const id = newId('post');
  const now = new Date().toISOString();
  db.transaction(() => {
    db.prepare("INSERT INTO community_posts (post_id, user_id, content, image_emoji, status, timestamp, updated_at, location_id) VALUES (?, ?, ?, NULL, 'visible', ?, ?, ?)")
      .run(id, req.user.user_id, parsed.content, now, now, parsed.locationId);
    parsed.images.forEach((im, i) => db.prepare('INSERT INTO post_images (image_id, post_id, position, image) VALUES (?, ?, ?, ?)').run(newId('pim'), id, i, im.image));
    C.setHashtags(id, parsed.content);
  })();
  res.status(201).json({ post_id: id });
});

router.put('/posts/:id', authMiddleware, (req, res) => {
  const post = db.prepare("SELECT * FROM community_posts WHERE post_id = ? AND status = 'visible'").get(req.params.id);
  if (!post || post.user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  const existing = new Set(db.prepare('SELECT image_id FROM post_images WHERE post_id = ?').all(post.post_id).map((r) => r.image_id));
  const body = req.body || {};
  // omitted images/location_id mean "unchanged"
  const merged = { ...body, images: body.images === undefined ? [...existing].map((image_id) => ({ image_id })) : body.images, location_id: body.location_id === undefined ? post.location_id : body.location_id };
  const parsed = parsePostBody(merged, { existingImageIds: existing });
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  if (parsed.images.some((i) => i.image) && C.dbIsFull()) return res.status(507).json({ error: 'พื้นที่เก็บรูปภาพของระบบเต็มชั่วคราว' });

  db.transaction(() => {
    const keep = new Set(parsed.images.filter((i) => i.image_id).map((i) => i.image_id));
    for (const id of existing) if (!keep.has(id)) db.prepare('DELETE FROM post_images WHERE image_id = ?').run(id);
    parsed.images.forEach((im, i) => {
      if (im.image_id) db.prepare('UPDATE post_images SET position = ? WHERE image_id = ?').run(i, im.image_id);
      else db.prepare('INSERT INTO post_images (image_id, post_id, position, image) VALUES (?, ?, ?, ?)').run(newId('pim'), post.post_id, i, im.image);
    });
    db.prepare('UPDATE community_posts SET content = ?, location_id = ?, updated_at = ?, image_emoji = NULL WHERE post_id = ?')
      .run(parsed.content, parsed.locationId, new Date().toISOString(), post.post_id);
    C.setHashtags(post.post_id, parsed.content);
  })();
  res.json({ post_id: post.post_id });
});

router.delete('/posts/:id', authMiddleware, (req, res) => {
  const post = db.prepare('SELECT user_id FROM community_posts WHERE post_id = ?').get(req.params.id);
  if (!post || post.user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  C.deletePost(req.params.id);
  res.json({ status: 'deleted' });
});

// ---- reactions -----------------------------------------------------------------------------------------------------------------
function reactionSummary(postId, userId) {
  const reactions = {};
  for (const r of db.prepare('SELECT type, COUNT(*) AS c FROM post_reactions WHERE post_id = ? GROUP BY type').all(postId)) reactions[r.type] = r.c;
  const mine = db.prepare('SELECT type FROM post_reactions WHERE post_id = ? AND user_id = ?').get(postId, userId);
  return { reactions, reaction_count: Object.values(reactions).reduce((a, b) => a + b, 0), my_reaction: mine ? mine.type : null };
}

function react(postId, userId, type) {
  const post = db.prepare("SELECT user_id, content FROM community_posts WHERE post_id = ? AND status = 'visible'").get(postId);
  const had = db.prepare('SELECT 1 FROM post_reactions WHERE post_id = ? AND user_id = ?').get(postId, userId);
  db.prepare(`INSERT INTO post_reactions (post_id, user_id, type, created_at) VALUES (?, ?, ?, ?)
    ON CONFLICT(post_id, user_id) DO UPDATE SET type = excluded.type`).run(postId, userId, type, new Date().toISOString());
  // told once per person per post: switching the emoji, or taking it back and giving it again, stays quiet
  if (!had && post.user_id !== userId) {
    C.notifyOnce(post.user_id, 'community_reaction', `${displayOf(userId)} แสดงความรู้สึกต่อโพสต์ของคุณ`, { post_id: postId, actor: userId });
  }
}

router.put('/posts/:id/reaction', authMiddleware, (req, res) => {
  const type = (req.body || {}).type;
  if (!C.REACTIONS.includes(type)) return res.status(400).json({ error: `ประเภทต้องเป็น ${C.REACTIONS.join(', ')}` });
  if (!isVisible(req.params.id)) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  react(req.params.id, req.user.user_id, type);
  res.json(reactionSummary(req.params.id, req.user.user_id));
});

router.delete('/posts/:id/reaction', authMiddleware, (req, res) => {
  if (!isVisible(req.params.id)) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  db.prepare('DELETE FROM post_reactions WHERE post_id = ? AND user_id = ?').run(req.params.id, req.user.user_id);
  res.json(reactionSummary(req.params.id, req.user.user_id));
});

// Older clients: tap = like, tap again = take it back.
router.post('/posts/:id/like', authMiddleware, (req, res) => {
  if (!isVisible(req.params.id)) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  const mine = db.prepare('SELECT type FROM post_reactions WHERE post_id = ? AND user_id = ?').get(req.params.id, req.user.user_id);
  if (mine) {
    db.prepare('DELETE FROM post_reactions WHERE post_id = ? AND user_id = ?').run(req.params.id, req.user.user_id);
    return res.json({ liked: false });
  }
  react(req.params.id, req.user.user_id, 'LIKE');
  res.json({ liked: true });
});

// ---- comments ------------------------------------------------------------------------------------------------------------------
function commentViews(rows, viewerId) {
  const authors = C.authorViews(rows.map((r) => r.user_id), viewerId);
  return rows.map((c) => ({
    comment_id: c.comment_id,
    post_id: c.post_id,
    author: authors.get(c.user_id),
    username: (authors.get(c.user_id) || {}).username,
    content: c.content || '',
    has_image: !!c.has_image,
    created_at: c.timestamp,
    timestamp: c.timestamp,
    edited: !!c.updated_at,
    is_mine: !!viewerId && viewerId === c.user_id,
  }));
}

router.get('/posts/:id/comments', (req, res) => {
  if (!isVisible(req.params.id)) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  const rows = db.prepare(`SELECT comment_id, post_id, user_id, content, timestamp, updated_at, (image IS NOT NULL) AS has_image
    FROM community_comments WHERE post_id = ? ORDER BY timestamp ASC, comment_id ASC LIMIT 300`).all(req.params.id);
  res.json({ comments: commentViews(rows, C.optionalUserId(req)) });
});

function parseComment(b, { allowKeep = false } = {}) {
  const content = typeof b.content === 'string' ? b.content.trim() : '';
  if (content.length > LIMITS.MAX_COMMENT_TEXT) return { error: `ความคิดเห็นยาวเกินไป (ไม่เกิน ${LIMITS.MAX_COMMENT_TEXT} ตัวอักษร)` };
  let image; // undefined = keep (edit only), null = none, string = new picture
  if (b.image === undefined && allowKeep) image = undefined;
  else if (b.image === null || b.image === undefined) image = null;
  else {
    const err = imageProblem(b.image, LIMITS.COMMENT_IMAGE_CHARS, 'รูปภาพ');
    if (err) return { error: err };
    image = b.image;
  }
  return { content, image };
}

router.post('/posts/:id/comments', authMiddleware, (req, res) => {
  const post = db.prepare("SELECT user_id, content FROM community_posts WHERE post_id = ? AND status = 'visible'").get(req.params.id);
  if (!post) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  const parsed = parseComment(req.body || {});
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  if (!parsed.content && !parsed.image) return res.status(400).json({ error: 'เขียนข้อความหรือแนบรูป' });
  if (C.recentCount('community_comments', 'user_id', 'timestamp', req.user.user_id) >= LIMITS.COMMENTS_PER_DAY) {
    return res.status(429).json({ error: `คอมเมนต์ได้สูงสุด ${LIMITS.COMMENTS_PER_DAY} ครั้งใน 24 ชั่วโมง` });
  }
  if (parsed.image && C.dbIsFull()) return res.status(507).json({ error: 'พื้นที่เก็บรูปภาพของระบบเต็มชั่วคราว คอมเมนต์ได้เฉพาะข้อความ' });
  const id = newId('cmt');
  db.prepare('INSERT INTO community_comments (comment_id, post_id, user_id, content, timestamp, image) VALUES (?, ?, ?, ?, ?, ?)')
    .run(id, req.params.id, req.user.user_id, parsed.content, new Date().toISOString(), parsed.image);
  if (post.user_id !== req.user.user_id) {
    notify(post.user_id, 'community_comment', `${displayOf(req.user.user_id)} แสดงความคิดเห็นในโพสต์ของคุณ: ${clip(parsed.content || '[รูปภาพ]')}`, { post_id: req.params.id, comment_id: id });
  }
  res.status(201).json({ comment_id: id });
});

const ownComment = (req) => {
  const c = db.prepare(`SELECT c.* FROM community_comments c JOIN community_posts p ON p.post_id = c.post_id
    WHERE c.comment_id = ? AND p.status = 'visible'`).get(req.params.id);
  return c && c.user_id === req.user.user_id ? c : null;
};

router.put('/comments/:id', authMiddleware, (req, res) => {
  const c = ownComment(req);
  if (!c) return res.status(404).json({ error: 'ไม่พบความคิดเห็น' });
  const parsed = parseComment(req.body || {}, { allowKeep: true });
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  const image = parsed.image === undefined ? c.image : parsed.image;
  if (!parsed.content && !image) return res.status(400).json({ error: 'เขียนข้อความหรือแนบรูป' });
  if (typeof parsed.image === 'string' && C.dbIsFull()) return res.status(507).json({ error: 'พื้นที่เก็บรูปภาพของระบบเต็มชั่วคราว' });
  db.prepare('UPDATE community_comments SET content = ?, image = ?, updated_at = ? WHERE comment_id = ?').run(parsed.content, image, new Date().toISOString(), c.comment_id);
  res.json({ comment_id: c.comment_id });
});

router.delete('/comments/:id', authMiddleware, (req, res) => {
  const c = ownComment(req);
  if (!c) return res.status(404).json({ error: 'ไม่พบความคิดเห็น' });
  db.prepare('DELETE FROM community_comments WHERE comment_id = ?').run(c.comment_id);
  res.json({ status: 'deleted' });
});

// ---- reports -------------------------------------------------------------------------------------------------------------------
router.post('/posts/:id/report', authMiddleware, (req, res) => {
  const post = db.prepare("SELECT user_id FROM community_posts WHERE post_id = ? AND status = 'visible'").get(req.params.id);
  if (!post) return res.status(404).json({ error: 'ไม่พบโพสต์' });
  if (post.user_id === req.user.user_id) return res.status(400).json({ error: 'รายงานโพสต์ของตัวเองไม่ได้' });
  const reason = String((req.body || {}).reason || '').trim();
  if (!reason || reason.length > LIMITS.REPORT_REASON) return res.status(400).json({ error: `ระบุเหตุผล (ไม่เกิน ${LIMITS.REPORT_REASON} ตัวอักษร)` });
  const added = db.prepare('INSERT OR IGNORE INTO post_reports (post_id, reporter_user_id, reason, created_at) VALUES (?, ?, ?, ?)').run(req.params.id, req.user.user_id, reason, new Date().toISOString()).changes;
  if (!added) return res.status(409).json({ error: 'คุณรายงานโพสต์นี้ไปแล้ว' });
  res.status(201).json({ status: 'reported' });
});

// ---- search and place tagging --------------------------------------------------------------------------------------------------
router.get('/search', (req, res) => {
  const viewerId = C.optionalUserId(req);
  const q = String(req.query.q || '').trim().slice(0, 60);
  if (!q) return res.json({ users: [], tags: [], posts: [] });
  if (q.startsWith('#')) {
    const tag = q.slice(1).toLowerCase();
    if (!tag) return res.json({ users: [], tags: [], posts: [] });
    const tags = db.prepare(`SELECT h.tag, COUNT(*) AS posts FROM post_hashtags h JOIN community_posts p ON p.post_id = h.post_id AND p.status = 'visible'
      WHERE h.tag LIKE ? ESCAPE '\\' GROUP BY h.tag ORDER BY posts DESC, h.tag LIMIT 10`).all(`${C.escapeLike(tag)}%`);
    return res.json({ users: [], tags, posts: [] });
  }
  const like = `%${C.escapeLike(q)}%`;
  const users = db.prepare(`SELECT user_id FROM users WHERE is_admin = 0 AND username NOT LIKE 'deleted-%' AND (username LIKE ? ESCAPE '\\' OR display_name LIKE ? ESCAPE '\\')
    ORDER BY username LIMIT 10`).all(like, like);
  const authors = C.authorViews(users.map((u) => u.user_id), viewerId);
  const posts = db.prepare("SELECT * FROM community_posts WHERE status = 'visible' AND content LIKE ? ESCAPE '\\' ORDER BY timestamp DESC, post_id DESC LIMIT 20").all(like);
  res.json({ users: users.map((u) => authors.get(u.user_id)), tags: [], posts: C.postViews(posts, viewerId) });
});

// Quick picks for the place tag: where the traveler booked a stay and where they checked in.
router.get('/suggestions', authMiddleware, (req, res) => {
  const booked = db.prepare(`SELECT l.location_id, l.name, l.province, MAX(br.status = 'confirmed') AS confirmed, MAX(br.requested_at) AS at
    FROM booking_requests br JOIN hotel_offers ho ON ho.offer_id = br.offer_id JOIN hotels h ON h.hotel_id = ho.hotel_id JOIN locations l ON l.location_id = h.location_id
    WHERE br.user_id = ? AND br.status IN ('requested', 'confirmed') GROUP BY l.location_id ORDER BY confirmed DESC, at DESC LIMIT 5`).all(req.user.user_id)
    .map((r) => ({ location_id: r.location_id, name: r.name, province: r.province, confirmed: !!r.confirmed }));
  const checkedIn = db.prepare(`SELECT l.location_id, l.name, l.province, MAX(t.timestamp) AS at FROM travel_history t JOIN locations l ON l.location_id = t.location_id
    WHERE t.user_id = ? AND t.status = 'success' GROUP BY l.location_id ORDER BY at DESC LIMIT 5`).all(req.user.user_id)
    .map((r) => ({ location_id: r.location_id, name: r.name, province: r.province }));
  res.json({ booked, checked_in: checkedIn });
});

module.exports = router;
