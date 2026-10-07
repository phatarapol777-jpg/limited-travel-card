const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let alice;
let locId;
let tplId;

const body = (over = {}) => ({
  name: 'ร้านทดสอบ', province: 'เชียงใหม่', latitude: 18.8, longitude: 98.9, mission_title: 'ภารกิจ', card_name: 'การ์ดสถานที่', card_rarity: 'rare', ...over,
});

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  alice = await s.register('alice');
});
test.after(() => s.stop());

test('the old payload shape (no artwork fields, legacy rarity) still works, so the PHP admin keeps working', async () => {
  const r = await s.call('POST', '/admin/locations', body({ card_rarity: 'epic' }), adm.token);
  assert.equal(r.status, 201);
  const list = (await s.call('GET', '/admin/locations', undefined, adm.token)).body.locations.find((l) => l.location_id === r.body.location_id);
  assert.equal(list.card.rarity, 'special');
  assert.equal(list.card.has_image, false);
  assert.equal(list.card.mint_limit, null);
});

test('artwork, story and mint limit can be set when creating a location', async () => {
  const r = await s.call('POST', '/admin/locations', body({ name: 'มีรูป', card_image: TINY_JPEG, card_lore: 'เรื่องเล่าของสถานที่', card_mint_limit: 200 }), adm.token);
  assert.equal(r.status, 201);
  locId = r.body.location_id;
  tplId = r.body.template_id;
  const card = (await s.call('GET', '/admin/locations', undefined, adm.token)).body.locations.find((l) => l.location_id === locId).card;
  assert.equal(card.has_image, true);
  assert.equal(card.lore, 'เรื่องเล่าของสถานที่');
  assert.equal(card.mint_limit, 200);
});

test('the location list never contains the image data, but the image is public', async () => {
  const raw = JSON.stringify((await s.call('GET', '/admin/locations', undefined, adm.token)).body);
  assert.equal(raw.includes('base64'), false);
  const media = await s.call('GET', `/media/card/${tplId}`);
  assert.equal(media.status, 200);
  assert.equal(media.res.headers.get('content-type'), 'image/jpeg');
});

test('update: replace the artwork, keep it when the field is omitted, remove it explicitly', async () => {
  const base = body({ name: 'มีรูป' });
  assert.equal((await s.call('PUT', `/admin/locations/${locId}`, base, adm.token)).status, 200);
  assert.equal((await s.call('GET', '/admin/locations', undefined, adm.token)).body.locations.find((l) => l.location_id === locId).card.has_image, true, 'omitted = unchanged');
  assert.equal((await s.call('PUT', `/admin/locations/${locId}`, { ...base, remove_card_image: true }, adm.token)).status, 200);
  assert.equal((await s.call('GET', '/admin/locations', undefined, adm.token)).body.locations.find((l) => l.location_id === locId).card.has_image, false);
  assert.equal((await s.call('GET', `/media/card/${tplId}`)).status, 404);
  assert.equal((await s.call('PUT', `/admin/locations/${locId}`, { ...base, card_image: TINY_JPEG }, adm.token)).status, 200);
  assert.equal((await s.call('GET', `/media/card/${tplId}`)).status, 200);
});

test('validation: bad image, long story, bad limit, limit below what was already given', async () => {
  const base = body({ name: 'มีรูป' });
  const put = (over) => s.call('PUT', `/admin/locations/${locId}`, { ...base, ...over }, adm.token);
  assert.equal((await put({ card_image: 'not-an-image' })).status, 400);
  assert.equal((await put({ card_image: 'data:image/png;base64,AAAA' })).status, 400);
  assert.equal((await put({ card_lore: 'x'.repeat(501) })).status, 400);
  for (const bad of [0, -5, 1.5, 'abc', 1_000_000]) assert.equal((await put({ card_mint_limit: bad })).status, 400, String(bad));
  assert.equal((await put({ card_mint_limit: '' })).status, 200, 'blank = unlimited');
  assert.equal((await s.call('GET', '/admin/locations', undefined, adm.token)).body.locations.find((l) => l.location_id === locId).card.mint_limit, null);

  const db = s.sql();
  db.prepare('UPDATE card_templates SET minted_count = 10 WHERE template_id = ?').run(tplId);
  db.close();
  const low = await put({ card_mint_limit: 5 });
  assert.equal(low.status, 400);
  assert.match(low.body.error, /10 ใบ/);
  assert.equal((await put({ card_mint_limit: 10 })).status, 200);
});

test('only admins can change location cards', async () => {
  assert.equal((await s.call('PUT', `/admin/locations/${locId}`, body({ card_image: TINY_JPEG }), alice.token)).status, 403);
});

test('coordinates must be real latitude / longitude values (a missing decimal point is rejected)', async () => {
  for (const bad of [{ longitude: 10328192519501052 }, { longitude: 'abc' }, { latitude: 200 }, { latitude: -91 }, { longitude: -181 }, { latitude: null }]) {
    const r = await s.call('POST', '/admin/locations', body({ name: 'พิกัดผิด', ...bad }), adm.token);
    assert.equal(r.status, 400, JSON.stringify(bad));
  }
  const ok = await s.call('POST', '/admin/locations', body({ name: 'พิกัดถูก', latitude: '16.2058', longitude: '103.2819' }), adm.token);
  assert.equal(ok.status, 201);
  assert.equal((await s.call('PUT', `/admin/locations/${locId}`, body({ name: 'มีรูป', longitude: 10328192519501052 }), adm.token)).status, 400);
});

test('the public place list says which places have a picture, without any image data', async () => {
  await s.call('PUT', `/admin/locations/${locId}`, body({ name: 'มีรูป', card_image: TINY_JPEG }), adm.token);
  const raw = await s.call('GET', '/catalog/locations');
  assert.equal(JSON.stringify(raw.body).includes('base64'), false);
  const withPic = raw.body.locations.find((l) => l.location_id === locId);
  assert.equal(withPic.card_has_image, true);
  assert.equal(withPic.card_template_id, tplId);
  assert.ok(withPic.card_image_rev > 0);
  const without = raw.body.locations.find((l) => l.name === 'ร้านทดสอบ');
  assert.equal(without.card_has_image, false);
  const before = withPic.card_image_rev;
  // a different (bigger) picture changes the revision, which busts the cache
  const bigger = `data:image/jpeg;base64,${Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(900, 7), Buffer.from([0xff, 0xd9])]).toString('base64')}`;
  await s.call('PUT', `/admin/locations/${locId}`, body({ name: 'มีรูป', card_image: bigger }), adm.token);
  const after = (await s.call('GET', '/catalog/locations')).body.locations.find((l) => l.location_id === locId).card_image_rev;
  assert.notEqual(after, before);
  assert.equal(raw.body.locations.length, new Set(raw.body.locations.map((l) => l.location_id)).size, 'one row per place');
});

