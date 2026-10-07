const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');
const { REGIONS, REGION_OF, rankFor } = require('../src/services/profileService');

let s;
let adm;
let alice;
let bob;

async function giveCard(user, rarity) {
  const pack = await s.call('POST', '/admin/blind-packs', { name: `สุ่ม ${rarity}`, rarity, count: 1, card_image: TINY_JPEG }, adm.token);
  const codes = (await s.call('GET', `/admin/blind-packs/${pack.body.template_id}/codes`, undefined, adm.token)).body.codes;
  return (await s.call('POST', '/cards/activate', { payload: codes[0].payload }, user.token)).body.card;
}

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  alice = await s.register('alice');
  bob = await s.register('bob');
});
test.after(() => s.stop());

test('there are 77 provinces, each in exactly one region', () => {
  const all = Object.values(REGIONS).flat();
  assert.equal(all.length, 77);
  assert.equal(new Set(all).size, 77);
  assert.equal(REGION_OF.get('เชียงใหม่'), 'เหนือ');
  assert.equal(REGION_OF.get('บึงกาฬ'), 'ตะวันออกเฉียงเหนือ');
});

test('collector rank thresholds', () => {
  assert.equal(rankFor(0).name, 'มือใหม่');
  assert.equal(rankFor(99).name, 'มือใหม่');
  assert.equal(rankFor(100).name, 'นักสะสม');
  assert.equal(rankFor(299).level, 2);
  assert.equal(rankFor(300).name, 'ชำนาญ');
  assert.equal(rankFor(800).name, 'ผู้เชี่ยวชาญ');
  assert.equal(rankFor(5000).name, 'ตำนาน');
  assert.equal(rankFor(5000).next_min, null);
  assert.equal(rankFor(0).next_min, 100);
});

test('points: normal 10, rare 50, special 200; rank follows', async () => {
  await giveCard(alice, 'normal');
  await giveCard(alice, 'rare');
  const special = await giveCard(alice, 'special');
  const p = (await s.call('GET', '/profile/me', undefined, alice.token)).body;
  assert.equal(p.stats.collector_points, 260);
  assert.deepEqual(p.stats.by_rarity, { normal: 1, rare: 1, special: 1 });
  assert.equal(p.stats.total_cards, 3);
  assert.equal(p.stats.rank.name, 'นักสะสม');
  assert.equal(p.stats.rank.next_name, 'ชำนาญ');
  assert.equal(p.stats.places_conquered, 0, 'blind-pack cards are not places');
  s.special = special;
});

test('places and regional progress come from quest / location cards only', async () => {
  // kiosk-style check-in at the seeded Chiang Mai location through the real award path
  const db = s.sql();
  const loc = db.prepare("SELECT l.location_id, t.template_id FROM locations l JOIN missions m ON m.location_id = l.location_id JOIN card_templates t ON t.mission_id = m.mission_id WHERE l.province = 'เชียงใหม่'").get();
  const now = new Date().toISOString();
  const cardId = 'card-test-north';
  db.prepare(`INSERT INTO all_cards (card_instance_id, template_id, owner_user_id, unique_code, acquired_at, serial_number, activation_status, card_type, claimed_at)
    VALUES (?, ?, ?, 'code-north', ?, 99, 'CLAIMED', 'QUEST_LOCATION', ?)`).run(cardId, loc.template_id, bob.id, now, now);
  db.close();
  const p = (await s.call('GET', '/profile/me', undefined, bob.token)).body;
  assert.equal(p.stats.places_conquered, 1);
  const north = p.stats.regions.find((r) => r.region === 'ภาคเหนือ');
  assert.deepEqual([north.collected, north.total, north.percent], [1, 1, 100]);
  const south = p.stats.regions.find((r) => r.region === 'ภาคใต้');
  assert.equal(south.percent, 0);
  const central = p.stats.regions.find((r) => r.region === 'ภาคกลาง');
  assert.deepEqual([central.collected, central.total], [0, 2]);
});

test('pins: up to 5, owned cards only, no duplicates, order kept', async () => {
  const mine = (await s.call('GET', '/cards', undefined, alice.token)).body.cards;
  const ids = mine.map((c) => c.card_instance_id);
  assert.equal((await s.call('PUT', '/profile/pins', { card_instance_ids: ids })).status, 401);
  assert.equal((await s.call('PUT', '/profile/pins', { card_instance_ids: 'x' }, alice.token)).status, 400);
  assert.equal((await s.call('PUT', '/profile/pins', { card_instance_ids: [ids[0], ids[0]] }, alice.token)).status, 400, 'duplicates');
  assert.equal((await s.call('PUT', '/profile/pins', { card_instance_ids: Array(6).fill('x').map((_, i) => `c${i}`) }, alice.token)).status, 400, 'more than 5');
  const bobCards = (await s.call('GET', '/cards', undefined, bob.token)).body.cards;
  assert.equal((await s.call('PUT', '/profile/pins', { card_instance_ids: [bobCards[0].card_instance_id] }, alice.token)).status, 400, "someone else's card");

  const order = [ids[2], ids[0]];
  const r = await s.call('PUT', '/profile/pins', { card_instance_ids: order }, alice.token);
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.pins.map((c) => c.card_instance_id), order);
  assert.equal((await s.call('PUT', '/profile/pins', { card_instance_ids: [] }, alice.token)).body.pins.length, 0);
  await s.call('PUT', '/profile/pins', { card_instance_ids: order }, alice.token);
});

test("another traveler's profile shows name, pins with serials and stats, but no contact details", async () => {
  const p = await s.call('GET', `/profile/${alice.username}`, undefined, bob.token);
  assert.equal(p.status, 200);
  assert.equal(p.body.pins.length, 2);
  assert.ok(p.body.pins.every((c) => c.serial_label && c.rarity));
  assert.equal(JSON.stringify(p.body).includes('@x.com'), false);
  assert.equal(JSON.stringify(p.body).includes('password'), false);
  assert.equal((await s.call('GET', `/profile/${alice.username}`)).status, 401);
  assert.equal((await s.call('GET', '/profile/nobody-at-all', undefined, bob.token)).status, 404);
  assert.equal((await s.call('GET', '/profile/admin', undefined, bob.token)).status, 404, 'admin accounts have no public profile');
});

test('a traded-away pinned card leaves the showcase and the points', async () => {
  const pins = (await s.call('GET', '/profile/me', undefined, alice.token)).body.pins;
  const pinned = pins[0];
  const before = (await s.call('GET', '/profile/me', undefined, alice.token)).body.stats.collector_points;
  const o = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: pinned.card_instance_id }, alice.token);
  assert.equal((await s.call('GET', '/profile/me', undefined, alice.token)).body.pins.length, 2, 'still shown while only locked in a pending trade');
  await s.call('POST', `/trades/${o.body.trade.trade_id}/accept`, {}, bob.token);
  const after = (await s.call('GET', '/profile/me', undefined, alice.token)).body;
  assert.equal(after.pins.length, 1);
  assert.equal(after.pins.some((c) => c.card_instance_id === pinned.card_instance_id), false);
  assert.ok(after.stats.collector_points < before);
  // the new owner does not inherit the pin
  const bobProfile = (await s.call('GET', '/profile/me', undefined, bob.token)).body;
  assert.equal(bobProfile.pins.some((c) => c.card_instance_id === pinned.card_instance_id), false);
});
