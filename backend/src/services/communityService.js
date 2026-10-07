const fs = require('fs');
const db = require('../db');
const { SESSION_MAX_AGE_MS } = require('../util');

// Pictures live in the database (there is no object storage), so they are small and capped. The whole database is also the
// backup snapshot, so new pictures are refused once the file grows past DB_LIMIT_BYTES.
const LIMITS = {
  POST_IMAGE_CHARS: 45_000,
  COMMENT_IMAGE_CHARS: 35_000,
  AVATAR_CHARS: 25_000,
  COVER_CHARS: 90_000,
  MAX_POST_IMAGES: 10,
  MAX_POST_TEXT: 2000,
  MAX_COMMENT_TEXT: 1000,
  MAX_BIO: 200,
  MAX_DISPLAY_NAME: 30,
  MAX_HASHTAGS: 10,
  POSTS_PER_DAY: 20,
  COMMENTS_PER_DAY: 100,
  REPORT_REASON: 200,
  DB_LIMIT_BYTES: (parseInt(process.env.COMMUNITY_DB_LIMIT_MB, 10) || 70) * 1024 * 1024,
};
const REACTIONS = ['LIKE', 'LOVE', 'WOW', 'SAD', 'ANGRY'];
const DAY_MS = 24 * 60 * 60 * 1000;
const MONTHS_TH = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];

/** Signed-in user id from the bearer token, or null (also null when the session is older than the 30-day limit). */
function optionalUserId(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return null;
  const session = db.prepare('SELECT user_id, created_at FROM sessions WHERE token = ?').get(token);
  if (!session || Date.now() - new Date(session.created_at).getTime() > SESSION_MAX_AGE_MS) return null;
  return session.user_id;
}

/** "2026-10" for a moment, in Thailand time (UTC+7). */
function bangkokMonth(ms = Date.now()) {
  return new Date(ms + 7 * 3600 * 1000).toISOString().slice(0, 7);
}

function monthLabel(ym) {
  const [y, m] = ym.split('-').map(Number);
  return `${MONTHS_TH[m - 1]} ${y + 543}`;
}

function dbIsFull() {
  try {
    return fs.statSync(db.name).size > LIMITS.DB_LIMIT_BYTES;
  } catch {
    return false;
  }
}

function hashtagsOf(text) {
  const found = new Set();
  for (const m of String(text || '').matchAll(/#([\p{L}\p{M}\p{N}_]{1,40})/gu)) {
    found.add(m[1].toLowerCase());
    if (found.size >= LIMITS.MAX_HASHTAGS) break;
  }
  return [...found];
}

const escapeLike = (q) => q.replace(/[%_\\]/g, '\\$&');

function inList(ids) {
  return ids.map(() => '?').join(',');
}

// ---- who wrote it: the only identity the community ever shows ------------------------------------------------------------------
function authorViews(userIds, viewerId = null) {
  const ids = [...new Set(userIds)];
  const map = new Map();
  if (!ids.length) return map;
  const rows = db.prepare(`SELECT u.user_id, u.username, u.display_name, u.profile_rev, (u.avatar IS NOT NULL) AS has_avatar, u.is_badge_visible,
      b.badge_id, b.icon, b.title, b.rank_position, b.awarded_month
    FROM users u LEFT JOIN user_badges b ON b.badge_id = u.selected_badge_id AND b.user_id = u.user_id
    WHERE u.user_id IN (${inList(ids)})`).all(...ids);
  const followed = new Set(viewerId ? db.prepare(`SELECT following_user_id FROM follows WHERE follower_user_id = ? AND following_user_id IN (${inList(ids)})`).all(viewerId, ...ids).map((f) => f.following_user_id) : []);
  for (const r of rows) {
    const gone = r.username.startsWith('deleted-');
    map.set(r.user_id, {
      is_me: !!viewerId && viewerId === r.user_id,
      is_following: followed.has(r.user_id),
      username: gone ? 'deleted' : r.username,
      display_name: gone ? 'ผู้ใช้ที่ลบบัญชี' : (r.display_name || r.username),
      has_avatar: !gone && !!r.has_avatar,
      avatar_rev: r.profile_rev,
      badge: !gone && r.is_badge_visible && r.badge_id ? { badge_id: r.badge_id, icon: r.icon, title: r.title, rank: r.rank_position, month: r.awarded_month } : null,
    });
  }
  return map;
}

const authorView = (userId, viewerId = null) => authorViews([userId], viewerId).get(userId) || null;

// ---- posts ---------------------------------------------------------------------------------------------------------------------
function postViews(rows, viewerId) {
  if (!rows.length) return [];
  const ids = rows.map((r) => r.post_id);
  const marks = inList(ids);
  const authors = authorViews(rows.map((r) => r.user_id), viewerId);

  const images = new Map();
  for (const i of db.prepare(`SELECT image_id, post_id FROM post_images WHERE post_id IN (${marks}) ORDER BY position`).all(...ids)) {
    images.set(i.post_id, [...(images.get(i.post_id) || []), i.image_id]);
  }
  const reactions = new Map();
  for (const r of db.prepare(`SELECT post_id, type, COUNT(*) AS c FROM post_reactions WHERE post_id IN (${marks}) GROUP BY post_id, type`).all(...ids)) {
    reactions.set(r.post_id, { ...(reactions.get(r.post_id) || {}), [r.type]: r.c });
  }
  const comments = new Map(db.prepare(`SELECT post_id, COUNT(*) AS c FROM community_comments WHERE post_id IN (${marks}) GROUP BY post_id`).all(...ids).map((r) => [r.post_id, r.c]));
  const mine = new Map();
  const reported = new Set();
  if (viewerId) {
    for (const r of db.prepare(`SELECT post_id, type FROM post_reactions WHERE user_id = ? AND post_id IN (${marks})`).all(viewerId, ...ids)) mine.set(r.post_id, r.type);
    for (const r of db.prepare(`SELECT post_id FROM post_reports WHERE reporter_user_id = ? AND post_id IN (${marks})`).all(viewerId, ...ids)) reported.add(r.post_id);
  }
  const locIds = [...new Set(rows.map((r) => r.location_id).filter(Boolean))];
  const locations = new Map();
  if (locIds.length) {
    for (const l of db.prepare(`SELECT location_id, name, province FROM locations WHERE location_id IN (${inList(locIds)})`).all(...locIds)) locations.set(l.location_id, l);
  }
  const tags = new Map();
  for (const t of db.prepare(`SELECT post_id, tag FROM post_hashtags WHERE post_id IN (${marks})`).all(...ids)) tags.set(t.post_id, [...(tags.get(t.post_id) || []), t.tag]);

  return rows.map((p) => {
    const counts = reactions.get(p.post_id) || {};
    const total = Object.values(counts).reduce((a, b) => a + b, 0);
    const author = authors.get(p.user_id);
    return {
      post_id: p.post_id,
      author,
      username: author ? author.username : null,
      content: p.content || '',
      image_emoji: p.image_emoji || null,
      images: images.get(p.post_id) || [],
      location: p.location_id ? locations.get(p.location_id) || null : null,
      hashtags: tags.get(p.post_id) || [],
      created_at: p.timestamp,
      timestamp: p.timestamp,
      updated_at: p.updated_at || null,
      reactions: counts,
      reaction_count: total,
      like_count: total,
      my_reaction: mine.get(p.post_id) || null,
      liked_by_me: mine.has(p.post_id),
      comment_count: comments.get(p.post_id) || 0,
      is_mine: !!viewerId && viewerId === p.user_id,
      reported_by_me: reported.has(p.post_id),
    };
  });
}

function setHashtags(postId, text) {
  db.prepare('DELETE FROM post_hashtags WHERE post_id = ?').run(postId);
  for (const t of hashtagsOf(text)) db.prepare('INSERT OR IGNORE INTO post_hashtags (post_id, tag) VALUES (?, ?)').run(postId, t);
}

/** Posts from old versions have no hashtag rows yet; fill them in once (INSERT OR IGNORE keeps this safe to repeat). */
function backfillHashtags() {
  const rows = db.prepare(`SELECT post_id, content FROM community_posts WHERE content LIKE '%#%' AND post_id NOT IN (SELECT post_id FROM post_hashtags)`).all();
  for (const r of rows) setHashtags(r.post_id, r.content);
  return rows.length;
}

function deletePost(postId) {
  db.transaction(() => {
    for (const t of ['post_images', 'post_hashtags', 'post_reactions', 'post_reports', 'community_comments', 'community_likes']) {
      db.prepare(`DELETE FROM ${t} WHERE post_id = ?`).run(postId);
    }
    db.prepare('DELETE FROM community_posts WHERE post_id = ?').run(postId);
  })();
}

function recentCount(table, userColumn, timeColumn, userId, now = Date.now()) {
  return db.prepare(`SELECT COUNT(*) AS c FROM ${table} WHERE ${userColumn} = ? AND ${timeColumn} >= ?`).get(userId, new Date(now - DAY_MS).toISOString()).c;
}

// ---- people --------------------------------------------------------------------------------------------------------------------
function communityStats(userId) {
  const one = (sql, ...args) => db.prepare(sql).get(...args).c;
  return {
    posts: one("SELECT COUNT(*) AS c FROM community_posts WHERE user_id = ? AND status = 'visible'", userId),
    places_checked_in: one("SELECT COUNT(DISTINCT location_id) AS c FROM travel_history WHERE user_id = ? AND status = 'success'", userId),
    followers: one('SELECT COUNT(*) AS c FROM follows WHERE following_user_id = ?', userId),
    following: one('SELECT COUNT(*) AS c FROM follows WHERE follower_user_id = ?', userId),
  };
}

const notifyOnce = (userId, type, text, data) => {
  const { notify } = require('./notify');
  const key = JSON.stringify(data);
  if (db.prepare('SELECT 1 FROM notifications WHERE user_id = ? AND type = ? AND data_json = ?').get(userId, type, key)) return;
  notify(userId, type, text, data);
};

module.exports = {
  LIMITS, REACTIONS, optionalUserId, bangkokMonth, monthLabel, dbIsFull, hashtagsOf, escapeLike, inList, authorViews, authorView, postViews,
  setHashtags, backfillHashtags, deletePost, recentCount, communityStats, notifyOnce,
};
