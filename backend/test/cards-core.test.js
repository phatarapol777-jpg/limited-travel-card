// Run with: node --test backend/test   (uses a throw-away data dir, never touches the real database)
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tc-cards-'));
process.env.DATA_DIR = dir;
process.env.BACKUP = 'off';
const db = require('../src/db');
require('../src/seed')();
const { mintCard, normalizeRarity, serialLabel, getCard } = require('../src/services/cardService');
const { awardCheckin } = require('../src/services/checkinService');

const user = (name) => {
  const id = `usr-${name}`;
  db.prepare("INSERT INTO users (user_id, username, password_hash, password_salt, first_name, last_name, email, created_at) VALUES (?, ?, 'x', 'x', ?, 'T', ?, ?)")
    .run(id, name, name, `${name}@x.com`, new Date().toISOString());
  return id;
};

test('rarity values are normalised (old clients send common/epic)', () => {
  assert.equal(normalizeRarity('common'), 'normal');
  assert.equal(normalizeRarity('epic'), 'special');
  assert.equal(normalizeRarity('RARE'), 'rare');
  assert.equal(normalizeRarity('nonsense'), 'normal');
});

test('serial labels: limited cards show #008/500, unlimited show #8', () => {
  assert.equal(serialLabel(8, 500), '#008/500');
  assert.equal(serialLabel(8, 5), '#008/5');
  assert.equal(serialLabel(8, 10000), '#00008/10000');
  assert.equal(serialLabel(8, null), '#8');
});

test('seeded data was migrated: spec rarities, card types, serials, counts', () => {
  const rarities = db.prepare('SELECT DISTINCT rarity FROM card_templates').all().map((r) => r.rarity).sort();
  assert.deepEqual(rarities, ['normal', 'rare', 'special']);
  const types = db.prepare('SELECT DISTINCT card_type FROM card_templates').all().map((r) => r.card_type).sort();
  assert.deepEqual(types, ['PHYSICAL_BLIND_PACK', 'QUEST_LOCATION']);
  const cards = db.prepare('SELECT * FROM all_cards').all();
  assert.ok(cards.length >= 3);
  for (const c of cards) {
    assert.equal(c.activation_status, 'CLAIMED');
    assert.ok(c.serial_number >= 1);
  }
});

test('mint limit: the last card is minted, the next one is refused, serials never repeat', () => {
  const u = user('minter');
  const tpl = db.prepare("SELECT template_id FROM card_templates WHERE type = 'mission' LIMIT 1").get().template_id;
  db.prepare('UPDATE card_templates SET mint_limit = 3, minted_count = 0 WHERE template_id = ?').run(tpl);
  db.prepare('DELETE FROM card_ownership_log WHERE card_instance_id IN (SELECT card_instance_id FROM all_cards WHERE template_id = ?)').run(tpl);
  db.prepare('DELETE FROM all_cards WHERE template_id = ?').run(tpl);
  const results = [1, 2, 3, 4, 5].map(() => mintCard({ templateId: tpl, userId: u }));
  assert.deepEqual(results.map((r) => r.ok), [true, true, true, false, false]);
  assert.equal(results[3].reason, 'sold_out');
  assert.deepEqual(results.slice(0, 3).map((r) => r.serial), [1, 2, 3]);
  assert.equal(getCard(results[2].cardId).serial_label, '#003/3');
  assert.equal(db.prepare('SELECT minted_count FROM card_templates WHERE template_id = ?').get(tpl).minted_count, 3);
});

test('a minted card is written to the ownership log', () => {
  const u = user('logged');
  const tpl = db.prepare("SELECT template_id FROM card_templates WHERE mint_limit IS NULL LIMIT 1").get().template_id;
  const r = mintCard({ templateId: tpl, userId: u });
  const log = db.prepare('SELECT * FROM card_ownership_log WHERE card_instance_id = ?').all(r.cardId);
  assert.equal(log.length, 1);
  assert.equal(log[0].to_user_id, u);
  assert.equal(log[0].reason, 'mint');
});

test('kiosk check-in still succeeds when the card is sold out, and says so', () => {
  const u = user('checkinuser');
  const loc = db.prepare('SELECT l.location_id, t.template_id FROM locations l JOIN missions m ON m.location_id = l.location_id JOIN card_templates t ON t.mission_id = m.mission_id LIMIT 1').get();
  db.prepare('UPDATE card_templates SET mint_limit = 1 WHERE template_id = ?').run(loc.template_id);
  db.prepare('UPDATE card_templates SET minted_count = 1 WHERE template_id = ?').run(loc.template_id);
  const result = awardCheckin(u, loc.location_id);
  assert.equal(result.awarded_cards.length, 0);
  assert.equal(result.sold_out_cards.length, 1);
  assert.equal(db.prepare("SELECT COUNT(*) AS c FROM travel_history WHERE user_id = ? AND status = 'success'").get(u).c, 1);
});

test('an unclaimed card has no owner and CLAIMED status only after being owned', () => {
  const tpl = db.prepare("SELECT template_id FROM card_templates WHERE mint_limit IS NULL LIMIT 1").get().template_id;
  const r = mintCard({ templateId: tpl, userId: null, withActivationCode: true });
  const card = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(r.cardId);
  assert.equal(card.owner_user_id, null);
  assert.equal(card.activation_status, 'UNCLAIMED');
  assert.match(card.activation_code, /^[a-f0-9]{32}$/);
});
