const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let alice;
let bob;
let questCard;
let locationId;

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  alice = await s.register('alice');
  bob = await s.register('bob');
  locationId = (await s.call('GET', '/catalog/locations')).body.locations[0].location_id;
  const q = await s.call('POST', '/quests', {
    title: 'ภารกิจ', location_id: locationId, description: 'd', cover_image: TINY_JPEG, permanent: true,
    card_name: 'การ์ดภารกิจ', card_image: TINY_JPEG, rarity: 'normal', mint_limit: 5,
  }, alice.token);
  await s.call('POST', `/admin/quests/${q.body.quest_id}/approve`, {}, adm.token);
  const payload = (await s.call('GET', `/quests/${q.body.quest_id}/qr`, undefined, alice.token)).body.payload;
  questCard = (await s.call('POST', '/quests/claim', { payload }, alice.token)).body.card;
});
test.after(() => s.stop());

test('the owner can register interest; it is only a demand log (no address, no payment)', async () => {
  const r = await s.call('POST', `/cards/${questCard.card_instance_id}/order-intent`, {}, alice.token);
  assert.equal(r.status, 201);
  assert.equal(r.body.registered, true);
  assert.match(r.body.message, /เปิดรับความสนใจสั่งซื้อการ์ดจริงแล้ว/);
  const again = await s.call('POST', `/cards/${questCard.card_instance_id}/order-intent`, {}, alice.token);
  assert.equal(again.status, 200);
  assert.equal(again.body.already_registered, true);
});

test('only the owner, only for quest/location cards, only when logged in', async () => {
  assert.equal((await s.call('POST', `/cards/${questCard.card_instance_id}/order-intent`, {}, bob.token)).status, 404);
  assert.equal((await s.call('POST', `/cards/${questCard.card_instance_id}/order-intent`, {})).status, 401);
  assert.equal((await s.call('POST', '/cards/nope/order-intent', {}, alice.token)).status, 404);
  const pack = await s.call('POST', '/admin/blind-packs', { name: 'สุ่ม', rarity: 'rare', count: 1, card_image: TINY_JPEG }, adm.token);
  const codes = (await s.call('GET', `/admin/blind-packs/${pack.body.template_id}/codes`, undefined, adm.token)).body.codes;
  const physical = (await s.call('POST', '/cards/activate', { payload: codes[0].payload }, alice.token)).body.card;
  const r = await s.call('POST', `/cards/${physical.card_instance_id}/order-intent`, {}, alice.token);
  assert.equal(r.status, 400);
});

test('admin sees demand per card design', async () => {
  await s.call('POST', `/cards/${questCard.card_instance_id}/order-intent`, {}, alice.token);
  const intents = (await s.call('GET', '/admin/order-intents', undefined, adm.token)).body.intents;
  assert.equal(intents.length, 1);
  assert.equal(intents[0].interested, 1);
  assert.equal((await s.call('GET', '/admin/order-intents', undefined, alice.token)).status, 403);
});

test('the old shipping-order routes are gone', async () => {
  assert.equal((await s.call('POST', '/cards/order', { card_instance_id: questCard.card_instance_id, shipping_address: 'x' }, alice.token)).status, 404);
  assert.equal((await s.call('POST', '/cards/transfer', { card_instance_id: questCard.card_instance_id, to_username: bob.username }, alice.token)).status, 404);
});
