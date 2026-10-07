const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let alice;
let bob;
let packId;
let codes;

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  alice = await s.register('alice');
  bob = await s.register('bob');
});
test.after(() => s.stop());

const pack = (over = {}) => ({ name: 'การ์ดสุ่ม Series 1', rarity: 'special', lore: 'เรื่องเล่า', count: 3, card_image: TINY_JPEG, ...over });

test('only admins create batches, with validation', async () => {
  assert.equal((await s.call('POST', '/admin/blind-packs', pack(), alice.token)).status, 403);
  for (const bad of [pack({ name: '' }), pack({ rarity: 'mythic' }), pack({ count: 0 }), pack({ count: 5001 }), pack({ count: 1.5 }), pack({ card_image: 'x' })]) {
    assert.equal((await s.call('POST', '/admin/blind-packs', bad, adm.token)).status, 400, JSON.stringify(bad).slice(0, 60));
  }
});

test('a batch creates unclaimed cards with unique 128-bit codes; codes are admin-only', async () => {
  const r = await s.call('POST', '/admin/blind-packs', pack(), adm.token);
  assert.equal(r.status, 201);
  packId = r.body.template_id;
  assert.equal((await s.call('GET', `/admin/blind-packs/${packId}/codes`, undefined, alice.token)).status, 403);
  const list = await s.call('GET', `/admin/blind-packs/${packId}/codes`, undefined, adm.token);
  codes = list.body.codes;
  assert.equal(codes.length, 3);
  assert.deepEqual(codes.map((c) => c.serial), ['#001/3', '#002/3', '#003/3']);
  assert.equal(new Set(codes.map((c) => c.payload)).size, 3);
  for (const c of codes) {
    assert.match(c.payload, /^TRVCARD\|[a-f0-9]{32}$/);
    assert.equal(c.status, 'UNCLAIMED');
  }
  const db = s.sql();
  const owners = db.prepare('SELECT DISTINCT owner_user_id FROM all_cards WHERE template_id = ?').all(packId);
  db.close();
  assert.deepEqual(owners, [{ owner_user_id: null }]);
  const packs = (await s.call('GET', '/admin/blind-packs', undefined, adm.token)).body.packs.find((p) => p.template_id === packId);
  assert.equal(packs.claimed, 0);
  assert.equal(packs.mint_limit, 3);
});

test('the first scan claims the card for good', async () => {
  const r = await s.call('POST', '/cards/activate', { payload: codes[0].payload }, alice.token);
  assert.equal(r.status, 201);
  assert.equal(r.body.card.serial_label, '#001/3');
  assert.equal(r.body.card.activation_status, 'CLAIMED');
  assert.equal(r.body.card.card_type, 'PHYSICAL_BLIND_PACK');
  assert.equal(r.body.card.rarity, 'special');
  assert.equal(JSON.stringify(r.body).includes('activation_code'), false, 'the code is never echoed back');
  const mine = (await s.call('GET', '/cards', undefined, alice.token)).body.cards;
  assert.ok(mine.some((c) => c.card_instance_id === r.body.card.card_instance_id));
  assert.equal(JSON.stringify(mine).includes(codes[0].payload.split('|')[1]), false);
  const db = s.sql();
  const log = db.prepare('SELECT reason, to_user_id FROM card_ownership_log WHERE card_instance_id = ?').all(r.body.card.card_instance_id);
  db.close();
  assert.deepEqual(log, [{ reason: 'activation', to_user_id: alice.id }]);
});

test('a second scan is refused and says who activated it and when', async () => {
  const again = await s.call('POST', '/cards/activate', { payload: codes[0].payload }, bob.token);
  assert.equal(again.status, 409);
  assert.match(again.body.error, new RegExp(`ถูกเปิดใช้งานไปแล้วโดยผู้ใช้ ${alice.username} เมื่อวันที่ 20\\d\\d-`));
  assert.equal(again.body.claimed_by, alice.username);
  const self = await s.call('POST', '/cards/activate', { payload: codes[0].payload }, alice.token);
  assert.equal(self.status, 409);
});

test('the message still names the first activator after the card changed hands', async () => {
  const db = s.sql();
  const card = db.prepare('SELECT card_instance_id FROM all_cards WHERE activation_code = ?').get(codes[0].payload.split('|')[1]);
  db.prepare('UPDATE all_cards SET owner_user_id = ? WHERE card_instance_id = ?').run(bob.id, card.card_instance_id);
  db.close();
  const again = await s.call('POST', '/cards/activate', { payload: codes[0].payload }, bob.token);
  assert.equal(again.body.claimed_by, alice.username);
});

test('two people scanning the same new card at once: exactly one wins', async () => {
  const results = await Promise.all([alice, bob].map((u) => s.call('POST', '/cards/activate', { payload: codes[1].payload }, u.token)));
  assert.deepEqual(results.map((r) => r.status).sort(), [201, 409]);
});

test('bad payloads are refused and repeated failures are throttled', async () => {
  const carol = await s.register('carol');
  for (const payload of ['', null, 'TRVCARD|short', `TRVCARD|${'g'.repeat(32)}`, `TRVCARD|${'0'.repeat(32)}`, `X|${'a'.repeat(32)}`]) {
    const r = await s.call('POST', '/cards/activate', { payload }, carol.token);
    assert.ok([400, 404].includes(r.status), String(payload));
  }
  assert.equal((await s.call('POST', '/cards/activate', { payload: codes[2].payload })).status, 401);
  let last;
  for (let i = 0; i < 25; i++) last = await s.call('POST', '/cards/activate', { payload: `TRVCARD|${'1'.repeat(32)}` }, carol.token);
  assert.equal(last.status, 429);
  // a throttled user cannot even use a valid code until the window passes
  assert.equal((await s.call('POST', '/cards/activate', { payload: codes[2].payload }, carol.token)).status, 429);
  // other users are unaffected
  assert.equal((await s.call('POST', '/cards/activate', { payload: codes[2].payload }, alice.token)).status, 201);
});

test('the unclaimed rest of the batch is not visible in public data', async () => {
  const listing = JSON.stringify((await s.call('GET', '/quests')).body) + JSON.stringify((await s.call('GET', '/catalog/locations')).body);
  assert.equal(listing.includes('TRVCARD'), false);
});
