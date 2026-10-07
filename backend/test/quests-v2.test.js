process.env.KIOSK_SECRET = 'test-secret';
const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let creator;
let other;
let loc;

const form = (over = {}) => ({
  title: 'ภารกิจทดสอบ', location_id: loc.location_id, description: 'ทำตามเงื่อนไข', cover_image: TINY_JPEG, permanent: true,
  card_name: 'การ์ดทดสอบ', card_image: TINY_JPEG, card_lore: 'เรื่องเล่า', rarity: 'rare', mint_limit: 10, ...over,
});
const submit = async (over) => (await s.call('POST', '/quests', form(over), creator.token)).body.quest_id;
const approve = (id) => s.call('POST', `/admin/quests/${id}/approve`, {}, adm.token);
const payloadOf = async (id) => (await s.call('GET', `/quests/${id}/qr`, undefined, creator.token)).body.payload;

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  creator = await s.register('creator');
  other = await s.register('other');
  loc = (await s.call('GET', '/catalog/locations')).body.locations[0];
});
test.after(() => s.stop());

test('a rejected quest can be fixed and sent again; images are kept when not replaced', async () => {
  const id = await submit();
  assert.equal((await s.call('POST', `/admin/quests/${id}/reject`, { reason: 'รูปไม่ชัด' }, adm.token)).status, 200);

  assert.equal((await s.call('PUT', `/quests/${id}`, form({ title: 'x' }), other.token)).status, 404, 'only the creator edits');
  assert.equal((await s.call('PUT', `/quests/${id}`, form({ title: '' }), creator.token)).status, 400);
  assert.equal((await s.call('PUT', `/quests/${id}`, form({ mint_limit: 0 }), creator.token)).status, 400);

  const edit = await s.call('PUT', `/quests/${id}`, form({ title: 'แก้แล้ว', mint_limit: 25, rarity: 'special', cover_image: undefined, card_image: undefined }), creator.token);
  assert.equal(edit.status, 200);
  const mine = (await s.call('GET', '/quests/mine', undefined, creator.token)).body.quests.find((q) => q.quest_id === id);
  assert.equal(mine.status, 'pending');
  assert.equal(mine.reject_reason, null);
  assert.equal(mine.title, 'แก้แล้ว');
  assert.equal(mine.card.mint_limit, 25);
  assert.equal(mine.card.rarity, 'special');
  assert.equal(mine.has_cover, true, 'the old cover stayed');
  assert.equal(mine.card.has_image, true, 'the old artwork stayed');

  assert.equal((await approve(id)).status, 200);
  assert.equal((await s.call('PUT', `/quests/${id}`, form(), creator.token)).status, 409, 'approved quests are not edited in place');
});

test('the creator can withdraw a waiting request or close a running quest', async () => {
  const waiting = await submit();
  assert.equal((await s.call('POST', `/quests/${waiting}/close`, {}, other.token)).status, 404);
  assert.equal((await s.call('POST', `/quests/${waiting}/close`, {}, creator.token)).status, 200);
  assert.equal((await s.call('POST', `/quests/${waiting}/close`, {}, creator.token)).status, 409);
  assert.equal((await s.call('PUT', `/quests/${waiting}`, form(), creator.token)).status, 409, 'a closed quest cannot be reopened by editing');

  const running = await submit();
  await approve(running);
  const payload = await payloadOf(running);
  const first = await s.register('first');
  assert.equal((await s.call('POST', '/quests/claim', { payload }, first.token)).status, 201);
  assert.equal((await s.call('POST', `/quests/${running}/close`, {}, creator.token)).status, 200);
  const late = await s.register('late');
  const r = await s.call('POST', '/quests/claim', { payload }, late.token);
  assert.equal(r.status, 409);
  assert.match(r.body.error, /ปิดแล้ว/);
  assert.equal((await s.call('GET', '/cards', undefined, first.token)).body.cards.length, 1, 'people who already claimed keep their card');
});

test('GPS check: needs a position, must be near the place, can be tuned and switched off', async () => {
  assert.equal((await s.call('PUT', '/admin/settings', { quest_geo_check: true }, adm.token)).status, 200);
  const id = await submit({ mint_limit: 50 });
  await approve(id);
  const payload = await payloadOf(id);
  const claim = (user, pos) => s.call('POST', '/quests/claim', { payload, ...pos }, user.token);
  const u = await s.register('walker');

  const none = await claim(u, {});
  assert.equal(none.status, 400);
  assert.equal(none.body.code, 'location_required');
  for (const bad of [{ lat: 'x', lng: 1 }, { lat: 200, lng: 1 }, { lat: 1, lng: 999 }, { lat: null, lng: null }]) assert.equal((await claim(u, bad)).status, 400, JSON.stringify(bad));

  const far = await claim(u, { lat: 0, lng: 0 });
  assert.equal(far.status, 403);
  assert.equal(far.body.code, 'too_far');
  assert.match(far.body.error, /เมตร/);

  const near = { lat: loc.latitude + 0.0027, lng: loc.longitude }; // roughly 300 m north
  assert.equal((await s.call('PUT', '/admin/settings', { quest_geo_radius_m: 200 }, adm.token)).status, 200);
  assert.equal((await claim(u, near)).status, 403, 'a smaller radius refuses 300 m');
  assert.equal((await s.call('PUT', '/admin/settings', { quest_geo_radius_m: 1000 }, adm.token)).status, 200);
  const ok = await claim(u, near);
  assert.equal(ok.status, 201, 'a failed GPS check did not use up the claim');

  assert.equal((await s.call('PUT', '/admin/settings', { quest_geo_check: false }, adm.token)).status, 200);
  const free = await s.register('anywhere');
  assert.equal((await claim(free, {})).status, 201, 'with the check off no position is needed');
});
