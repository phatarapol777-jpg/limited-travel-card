process.env.KIOSK_SECRET = 'test-secret';
const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let alice;
let bob;
let carol;

const heartbeat = (code, key) => fetch(`${s.base}/kiosk/${code}/heartbeat`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-kiosk-key': key }, body: '{}' });
const kiosks = async () => (await s.call('GET', '/admin/kiosks', undefined, adm.token)).body.kiosks;

async function packCards(name, count, rarity = 'rare') {
  const pack = await s.call('POST', '/admin/blind-packs', { name, rarity, count, card_image: TINY_JPEG }, adm.token);
  const codes = (await s.call('GET', `/admin/blind-packs/${pack.body.template_id}/codes`, undefined, adm.token)).body.codes;
  return { templateId: pack.body.template_id, codes };
}
const activate = async (user, payload) => (await s.call('POST', '/cards/activate', { payload }, user.token)).body.card;

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  alice = await s.register('alice');
  bob = await s.register('bob');
  carol = await s.register('carol');
});
test.after(() => s.stop());

// ---- kiosk keys ---------------------------------------------------------------------------------------------------
test('version-0 kiosk keys are unchanged (pinned), so kiosks already set up keep working', async () => {
  const k = (await kiosks()).find((x) => x.kiosk_code === 'KSK-001');
  assert.equal(k.kiosk_key, '8b5d76d03fa16aba2a5b');
  assert.equal(k.key_version, 0);
  assert.equal(k.disabled, false);
});

test('rotate key: the old key stops at once, the new one works, other kiosks are untouched', async () => {
  const before = await kiosks();
  const k1 = before.find((x) => x.kiosk_code === 'KSK-001');
  const k2 = before.find((x) => x.kiosk_code === 'KSK-002');
  assert.equal((await heartbeat('KSK-001', k1.kiosk_key)).status, 200);
  assert.equal((await s.call('POST', '/admin/kiosks/KSK-001/rotate-key', {}, alice.token)).status, 403);
  assert.equal((await s.call('POST', '/admin/kiosks/KSK-999/rotate-key', {}, adm.token)).status, 404);

  const rotated = await s.call('POST', '/admin/kiosks/KSK-001/rotate-key', {}, adm.token);
  assert.equal(rotated.status, 200);
  assert.notEqual(rotated.body.kiosk_key, k1.kiosk_key);
  assert.equal((await heartbeat('KSK-001', k1.kiosk_key)).status, 401, 'the leaked key is dead');
  assert.equal((await heartbeat('KSK-001', rotated.body.kiosk_key)).status, 200);
  const after = await kiosks();
  assert.equal(after.find((x) => x.kiosk_code === 'KSK-001').kiosk_key, rotated.body.kiosk_key);
  assert.equal(after.find((x) => x.kiosk_code === 'KSK-002').kiosk_key, k2.kiosk_key);
  const again = await s.call('POST', '/admin/kiosks/KSK-001/rotate-key', {}, adm.token);
  assert.notEqual(again.body.kiosk_key, rotated.body.kiosk_key, 'every rotation gives a fresh key');
});

test('disable / enable a kiosk: it cannot sign in, travelers cannot open it, and it leaves the setup list', async () => {
  const k = (await kiosks()).find((x) => x.kiosk_code === 'KSK-003');
  assert.equal((await heartbeat('KSK-003', k.kiosk_key)).status, 200);
  assert.equal((await s.call('POST', '/admin/kiosks/KSK-003/disable', {}, bob.token)).status, 403);
  assert.equal((await s.call('POST', '/admin/kiosks/KSK-003/disable', {}, adm.token)).status, 200);

  const blocked = await heartbeat('KSK-003', k.kiosk_key);
  assert.equal(blocked.status, 403);
  const body = await blocked.json();
  assert.equal(body.code, 'kiosk_disabled');
  assert.match(body.error, /ปิดใช้งาน/);
  const open = await s.call('POST', '/kiosk/open', { kiosk_code: 'KSK-003' }, alice.token);
  assert.equal(open.status, 409);
  assert.match(open.body.error, /ปิดใช้งาน/);
  assert.equal((await s.call('GET', '/catalog/kiosks')).body.kiosks.some((x) => x.kiosk_code === 'KSK-003'), false);
  assert.equal((await kiosks()).find((x) => x.kiosk_code === 'KSK-003').disabled, true);

  assert.equal((await s.call('POST', '/admin/kiosks/KSK-003/enable', {}, adm.token)).status, 200);
  assert.equal((await heartbeat('KSK-003', k.kiosk_key)).status, 200, 'the same key works again');
  assert.equal((await s.call('GET', '/catalog/kiosks')).body.kiosks.some((x) => x.kiosk_code === 'KSK-003'), true);
});

// ---- voided cards -------------------------------------------------------------------------------------------------
test('voiding a card removes it everywhere it could matter', async () => {
  const { templateId, codes } = await packCards('ชุดยกเลิก', 3);
  const c1 = await activate(alice, codes[0].payload);
  const c2 = await activate(alice, codes[1].payload);
  await s.call('PUT', '/profile/pins', { card_instance_ids: [c1.card_instance_id, c2.card_instance_id] }, alice.token);
  const pointsBefore = (await s.call('GET', '/profile/me', undefined, alice.token)).body.stats.collector_points;
  const offer = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: c2.card_instance_id }, alice.token);
  assert.equal(offer.status, 201);

  assert.equal((await s.call('POST', `/admin/cards/${c1.card_instance_id}/void`, { reason: 'พิมพ์ผิด' }, alice.token)).status, 403);
  assert.equal((await s.call('POST', '/admin/cards/nope/void', {}, adm.token)).status, 404);
  assert.equal((await s.call('POST', `/admin/cards/${c1.card_instance_id}/void`, { reason: 'พิมพ์ผิด' }, adm.token)).status, 200);
  assert.equal((await s.call('POST', `/admin/cards/${c1.card_instance_id}/void`, {}, adm.token)).status, 409, 'cannot void twice');

  // the pending offer of c2 is cancelled when c2 is voided; c2 leaves the trade and the collection
  assert.equal((await s.call('POST', `/admin/cards/${c2.card_instance_id}/void`, {}, adm.token)).status, 200);

  const mine = (await s.call('GET', '/cards', undefined, alice.token)).body.cards;
  assert.equal(mine.some((c) => [c1.card_instance_id, c2.card_instance_id].includes(c.card_instance_id)), false, 'gone from the collection');
  const profile = (await s.call('GET', '/profile/me', undefined, alice.token)).body;
  assert.equal(profile.pins.length, 0, 'gone from the showcase');
  assert.ok(profile.stats.collector_points < pointsBefore, 'no longer counts for points');

  const trades = (await s.call('GET', '/trades', undefined, bob.token)).body;
  assert.equal(trades.incoming.length, 0, 'the offer is cancelled');
  assert.equal((await s.call('POST', `/trades/${offer.body.trade.trade_id}/accept`, {}, bob.token)).status, 409);
  const notes = (await s.call('GET', '/notifications', undefined, alice.token)).body.notifications.filter((n) => n.type === 'card_voided');
  assert.equal(notes.length, 2, 'one notice per voided card');
  assert.ok(notes.every((n) => /ถูกยกเลิก/.test(n.text)));
  assert.ok(notes.some((n) => /พิมพ์ผิด/.test(n.text)), 'the reason is included');
  assert.equal((await s.call('GET', '/notifications', undefined, bob.token)).body.notifications.some((n) => n.type === 'trade_cancelled'), true);

  const again = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: c1.card_instance_id }, alice.token);
  assert.ok([404, 409].includes(again.status), 'a voided card cannot be offered');

  const db = s.sql();
  assert.equal(db.prepare("SELECT reason FROM card_ownership_log WHERE card_instance_id = ? ORDER BY rowid DESC LIMIT 1").get(c1.card_instance_id).reason, 'void');
  assert.equal(db.prepare('SELECT minted_count FROM card_templates WHERE template_id = ?').get(templateId).minted_count, 3, 'a voided card still counts as printed');
  db.close();
});

test('an unclaimed card can be voided and then says so when scanned; admin card search finds cards', async () => {
  const { codes } = await packCards('ยังไม่เปิด', 2, 'normal');
  const db = s.sql();
  const card = db.prepare('SELECT card_instance_id FROM all_cards WHERE activation_code = ?').get(codes[0].payload.split('|')[1]);
  db.close();
  assert.equal((await s.call('POST', `/admin/cards/${card.card_instance_id}/void`, { reason: 'หาย' }, adm.token)).status, 200);
  const scan = await s.call('POST', '/cards/activate', { payload: codes[0].payload }, carol.token);
  assert.equal(scan.status, 409);
  assert.equal(scan.body.code, 'voided');
  assert.doesNotMatch(scan.body.error, /ถูกเปิดใช้งานไปแล้วโดย/);
  assert.equal((await s.call('POST', '/cards/activate', { payload: codes[1].payload }, carol.token)).status, 201, 'the rest of the batch is fine');

  const found = (await s.call('GET', `/admin/cards?q=${carol.username}`, undefined, adm.token)).body.cards;
  assert.ok(found.length >= 1 && found.every((c) => c.owner_username === carol.username));
  assert.equal(JSON.stringify(found).includes('base64'), false);
  assert.equal((await s.call('GET', '/admin/cards', undefined, carol.token)).status, 403);
});

test('a voided quest/location card cannot be used for an order-intent', async () => {
  const loc = (await s.call('GET', '/catalog/locations')).body.locations[0].location_id;
  const q = await s.call('POST', '/quests', { title: 't', location_id: loc, description: 'd', cover_image: TINY_JPEG, permanent: true, card_name: 'ใบเควส', card_image: TINY_JPEG, rarity: 'rare', mint_limit: 9 }, alice.token);
  await s.call('POST', `/admin/quests/${q.body.quest_id}/approve`, {}, adm.token);
  s.questPayload = (await s.call('GET', `/quests/${q.body.quest_id}/qr`, undefined, alice.token)).body.payload;
  s.questTemplate = null;
  const mine = (await s.call('POST', '/quests/claim', { payload: s.questPayload }, alice.token)).body.card;
  s.questTemplate = mine.template_id;
  assert.equal((await s.call('POST', `/cards/${mine.card_instance_id}/order-intent`, {}, alice.token)).status, 201);
  assert.equal((await s.call('POST', `/admin/cards/${mine.card_instance_id}/void`, {}, adm.token)).status, 200);
  assert.equal((await s.call('POST', `/cards/${mine.card_instance_id}/order-intent`, {}, alice.token)).status, 404);
});

// ---- "order physical card" follow-up --------------------------------------------------------------------------------
test('telling interested people the card is ready: once each, admin only', async () => {
  const t = s.questTemplate;
  for (const u of [bob, carol]) {
    const card = (await s.call('POST', '/quests/claim', { payload: s.questPayload }, u.token)).body.card;
    assert.equal((await s.call('POST', `/cards/${card.card_instance_id}/order-intent`, {}, u.token)).status, 201);
  }
  const before = (await s.call('GET', '/admin/order-intents', undefined, adm.token)).body.intents.find((i) => i.template_id === t);
  assert.equal(before.interested, 3);
  assert.equal(before.unnotified, 3);

  assert.equal((await s.call('POST', `/admin/order-intents/${t}/notify`, {}, bob.token)).status, 403);
  assert.equal((await s.call('POST', '/admin/order-intents/nope/notify', {}, adm.token)).status, 404);
  const first = await s.call('POST', `/admin/order-intents/${t}/notify`, {}, adm.token);
  assert.equal(first.body.notified, 3);
  assert.equal((await s.call('POST', `/admin/order-intents/${t}/notify`, {}, adm.token)).body.notified, 0, 'nobody is told twice');
  for (const u of [alice, bob, carol]) {
    const n = (await s.call('GET', '/notifications', undefined, u.token)).body.notifications.filter((x) => x.type === 'order_ready');
    assert.equal(n.length, 1, u.username);
    assert.match(n[0].text, /พร้อมจัดส่ง/);
  }
  const after = (await s.call('GET', '/admin/order-intents', undefined, adm.token)).body.intents.find((i) => i.template_id === t);
  assert.equal(after.unnotified, 0);
});

// ---- community moderation -----------------------------------------------------------------------------------------------
test('admins can hide and restore posts; hidden posts take no likes or comments', async () => {
  const post = await s.call('POST', '/community/posts', { content: 'โพสต์ทดสอบการกลั่นกรอง' }, alice.token);
  const id = post.body.post_id;
  const publicIds = async () => (await s.call('GET', '/community/posts')).body.posts.map((p) => p.post_id);
  assert.ok((await publicIds()).includes(id));

  assert.equal((await s.call('GET', '/admin/community/posts', undefined, bob.token)).status, 403);
  const listed = (await s.call('GET', '/admin/community/posts', undefined, adm.token)).body.posts.find((p) => p.post_id === id);
  assert.equal(listed.username, alice.username);
  assert.equal(listed.status, 'visible');

  assert.equal((await s.call('PUT', `/admin/community/posts/${id}`, { status: 'deleted' }, adm.token)).status, 400);
  assert.equal((await s.call('PUT', '/admin/community/posts/nope', { status: 'hidden' }, adm.token)).status, 404);
  assert.equal((await s.call('PUT', `/admin/community/posts/${id}`, { status: 'hidden' }, bob.token)).status, 403);
  assert.equal((await s.call('PUT', `/admin/community/posts/${id}`, { status: 'hidden' }, adm.token)).status, 200);

  assert.equal((await publicIds()).includes(id), false);
  assert.equal((await s.call('POST', `/community/posts/${id}/like`, {}, bob.token)).status, 404);
  assert.equal((await s.call('POST', `/community/posts/${id}/comments`, { content: 'hi' }, bob.token)).status, 404);
  assert.equal((await s.call('GET', `/community/posts/${id}/comments`)).status, 404);
  assert.equal((await s.call('GET', '/admin/community/posts', undefined, adm.token)).body.posts.find((p) => p.post_id === id).status, 'hidden', 'admins still see it');

  assert.equal((await s.call('PUT', `/admin/community/posts/${id}`, { status: 'visible' }, adm.token)).status, 200);
  assert.ok((await publicIds()).includes(id));
  assert.equal((await s.call('POST', `/community/posts/${id}/like`, {}, bob.token)).status, 200);
});
