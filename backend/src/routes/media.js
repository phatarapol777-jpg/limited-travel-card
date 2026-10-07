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

module.exports = router;
