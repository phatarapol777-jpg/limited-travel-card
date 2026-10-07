const crypto = require('crypto');
const db = require('../db');
const { newId } = require('../util');

const RARITIES = ['normal', 'rare', 'special'];
const RARITY_POINTS = { normal: 10, rare: 50, special: 200 };
const CARD_TYPES = ['QUEST_LOCATION', 'PHYSICAL_BLIND_PACK'];

/** Older clients and the PHP admin still send common/epic; store the spec's names. */
function normalizeRarity(value) {
  const v = String(value || '').toLowerCase();
  if (v === 'common') return 'normal';
  if (v === 'epic') return 'special';
  return RARITIES.includes(v) ? v : 'normal';
}

/** "#008/500" for limited cards, "#8" when there is no limit. */
function serialLabel(serial, limit) {
  if (serial === null || serial === undefined) return null;
  if (limit === null || limit === undefined) return `#${serial}`;
  const width = Math.max(3, String(limit).length);
  return `#${String(serial).padStart(width, '0')}/${limit}`;
}

function logOwnership(cardId, fromUserId, toUserId, reason, tradeId = null) {
  db.prepare(`INSERT INTO card_ownership_log (log_id, card_instance_id, from_user_id, to_user_id, reason, trade_id, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)`).run(newId('own'), cardId, fromUserId, toUserId, reason, tradeId, new Date().toISOString());
}

/**
 * Creates one card instance of a template, enforcing the mint limit and assigning the next serial number.
 * Runs in a transaction, so two simultaneous claims can never exceed the limit or share a serial.
 * With no userId the card is created UNCLAIMED (a physical card waiting to be activated).
 */
const mintCard = db.transaction(({ templateId, userId = null, questCompletionId = null, withActivationCode = false, reason = 'mint' }) => {
  const template = db.prepare('SELECT * FROM card_templates WHERE template_id = ?').get(templateId);
  if (!template) return { ok: false, reason: 'no_template' };
  if (template.mint_limit !== null && template.minted_count >= template.mint_limit) {
    return { ok: false, reason: 'sold_out', template };
  }
  const serial = db.prepare('SELECT COALESCE(MAX(serial_number), 0) AS m FROM all_cards WHERE template_id = ?').get(templateId).m + 1;
  const cardId = newId('card');
  const now = new Date().toISOString();
  db.prepare(`INSERT INTO all_cards (card_instance_id, template_id, owner_user_id, unique_code, acquired_at, serial_number,
      activation_status, card_type, quest_completion_id, activation_code, claimed_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(cardId, templateId, userId, newId('code'), userId ? now : null, serial, userId ? 'CLAIMED' : 'UNCLAIMED',
      template.card_type, questCompletionId, withActivationCode ? crypto.randomBytes(16).toString('hex') : null, userId ? now : null);
  db.prepare('UPDATE card_templates SET minted_count = minted_count + 1 WHERE template_id = ?').run(templateId);
  if (userId) logOwnership(cardId, null, userId, reason);
  return { ok: true, cardId, serial, template };
});

/** The fields clients may see for a card instance (never the artwork data URL: that is served by the media route). */
const CARD_SELECT = `SELECT c.card_instance_id, c.template_id, c.owner_user_id, c.serial_number, c.activation_status, c.card_type,
    c.acquired_at, c.claimed_at, c.quest_completion_id, t.name, t.icon, t.color_hex, t.rarity, t.type, t.lore, t.mint_limit,
    t.minted_count, t.quest_id, (t.image IS NOT NULL) AS has_image, l.name AS location_name, l.province AS province
  FROM all_cards c JOIN card_templates t ON t.template_id = c.template_id
  LEFT JOIN locations l ON l.location_id = t.location_id`;

function cardView(row) {
  if (!row) return null;
  return { ...row, has_image: !!row.has_image, serial_label: serialLabel(row.serial_number, row.mint_limit) };
}

function getCard(cardId) {
  return cardView(db.prepare(`${CARD_SELECT} WHERE c.card_instance_id = ?`).get(cardId));
}

module.exports = { RARITIES, RARITY_POINTS, CARD_TYPES, normalizeRarity, serialLabel, mintCard, logOwnership, CARD_SELECT, cardView, getCard };
