const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');

const router = express.Router();

function attachOptionalUser(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return null;
  const session = db.prepare('SELECT user_id FROM sessions WHERE token = ?').get(token);
  return session ? session.user_id : null;
}

router.get('/posts', (req, res) => {
  const currentUserId = attachOptionalUser(req);
  const posts = db.prepare(`SELECT p.*, u.username, u.first_name, u.last_name
    FROM community_posts p JOIN users u ON u.user_id = p.user_id
    WHERE p.status = 'visible' ORDER BY p.timestamp DESC`).all();

  const result = posts.map((p) => {
    const likeCount = db.prepare('SELECT COUNT(*) AS c FROM community_likes WHERE post_id = ?').get(p.post_id).c;
    const commentCount = db.prepare('SELECT COUNT(*) AS c FROM community_comments WHERE post_id = ?').get(p.post_id).c;
    const likedByMe = currentUserId
      ? !!db.prepare('SELECT 1 FROM community_likes WHERE post_id = ? AND user_id = ?').get(p.post_id, currentUserId)
      : false;
    return { ...p, like_count: likeCount, comment_count: commentCount, liked_by_me: likedByMe };
  });
  res.json({ posts: result });
});

router.post('/posts', authMiddleware, (req, res) => {
  const { content, image_emoji } = req.body || {};
  if (!content || !content.trim()) return res.status(400).json({ error: 'Content required' });
  const postId = newId('post');
  db.prepare(`INSERT INTO community_posts (post_id, user_id, content, image_emoji, status, timestamp)
    VALUES (?, ?, ?, ?, ?, ?)`)
    .run(postId, req.user.user_id, content.trim(), image_emoji || null, 'visible', new Date().toISOString());
  res.status(201).json({ post_id: postId });
});

router.post('/posts/:id/like', authMiddleware, (req, res) => {
  const postId = req.params.id;
  const existing = db.prepare('SELECT 1 FROM community_likes WHERE post_id = ? AND user_id = ?').get(postId, req.user.user_id);
  if (existing) {
    db.prepare('DELETE FROM community_likes WHERE post_id = ? AND user_id = ?').run(postId, req.user.user_id);
    return res.json({ liked: false });
  }
  db.prepare('INSERT INTO community_likes (post_id, user_id) VALUES (?, ?)').run(postId, req.user.user_id);
  res.json({ liked: true });
});

router.get('/posts/:id/comments', (req, res) => {
  const comments = db.prepare(`SELECT c.*, u.username FROM community_comments c
    JOIN users u ON u.user_id = c.user_id WHERE c.post_id = ? ORDER BY c.timestamp ASC`).all(req.params.id);
  res.json({ comments });
});

router.post('/posts/:id/comments', authMiddleware, (req, res) => {
  const { content } = req.body || {};
  if (!content || !content.trim()) return res.status(400).json({ error: 'Content required' });
  const commentId = newId('cmt');
  db.prepare('INSERT INTO community_comments (comment_id, post_id, user_id, content, timestamp) VALUES (?, ?, ?, ?, ?)')
    .run(commentId, req.params.id, req.user.user_id, content.trim(), new Date().toISOString());
  res.status(201).json({ comment_id: commentId });
});

module.exports = router;
