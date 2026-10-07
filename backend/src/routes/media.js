const express = require('express');
const db = require('../db');

const router = express.Router();

function sendDataUrl(res, dataUrl) {
  const m = /^data:(image\/jpeg);base64,(.+)$/.exec(dataUrl || '');
  if (!m) return res.status(404).json({ error: 'ไม่พบภาพ' });
  res.set('Content-Type', m[1]);
  res.set('Cache-Control', 'public, max-age=60'); // short, so a replaced picture shows up within a minute
  res.set('X-Content-Type-Options', 'nosniff');
  res.send(Buffer.from(m[2], 'base64'));
}

// Public images, but only for quests an admin has approved (pending images stay private; see /api/quests/:id/images).
router.get('/quest/:id/cover', (req, res) => {
  const q = db.prepare("SELECT cover_image FROM quests WHERE quest_id = ? AND status IN ('approved', 'closed')").get(req.params.id);
  sendDataUrl(res, q && q.cover_image);
});

router.get('/card/:templateId', (req, res) => {
  const t = db.prepare(`SELECT t.image, t.quest_id, q.status FROM card_templates t LEFT JOIN quests q ON q.quest_id = t.quest_id WHERE t.template_id = ?`).get(req.params.templateId);
  if (!t || (t.quest_id && !['approved', 'closed'].includes(t.status))) return res.status(404).json({ error: 'ไม่พบภาพ' });
  sendDataUrl(res, t.image);
});

// Shop pictures: public only while the shop is approved (a suspended or unapproved shop shows nothing).
router.get('/merchant/:id/cover', (req, res) => {
  const m = db.prepare("SELECT cover_image FROM merchants WHERE merchant_id = ? AND approval_status = 'APPROVED'").get(req.params.id);
  sendDataUrl(res, m && m.cover_image);
});

router.get('/merchant-gallery/:imageId', (req, res) => {
  const r = db.prepare(`SELECT g.image FROM merchant_gallery g JOIN merchants m ON m.merchant_id = g.merchant_id
    WHERE g.image_id = ? AND m.approval_status = 'APPROVED'`).get(req.params.imageId);
  sendDataUrl(res, r && r.image);
});

router.get('/merchant-item/:itemId', (req, res) => {
  const r = db.prepare(`SELECT i.image FROM merchant_items i JOIN merchants m ON m.merchant_id = i.merchant_id
    WHERE i.item_id = ? AND m.approval_status = 'APPROVED'`).get(req.params.itemId);
  sendDataUrl(res, r && r.image);
});

// Community pictures: public only while the post is visible. Avatars and covers belong to the profile (a deleted account has none).
router.get('/post-image/:imageId', (req, res) => {
  const r = db.prepare(`SELECT i.image FROM post_images i JOIN community_posts p ON p.post_id = i.post_id WHERE i.image_id = ? AND p.status = 'visible'`).get(req.params.imageId);
  sendDataUrl(res, r && r.image);
});

router.get('/comment-image/:commentId', (req, res) => {
  const r = db.prepare(`SELECT c.image FROM community_comments c JOIN community_posts p ON p.post_id = c.post_id WHERE c.comment_id = ? AND p.status = 'visible'`).get(req.params.commentId);
  sendDataUrl(res, r && r.image);
});

router.get('/avatar/:username', (req, res) => {
  const u = db.prepare("SELECT avatar FROM users WHERE username = ? AND username NOT LIKE 'deleted-%'").get(req.params.username);
  sendDataUrl(res, u && u.avatar);
});

router.get('/cover/:username', (req, res) => {
  const u = db.prepare("SELECT cover FROM users WHERE username = ? AND username NOT LIKE 'deleted-%'").get(req.params.username);
  sendDataUrl(res, u && u.cover);
});

module.exports = router;
