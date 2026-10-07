const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let alice;
let bob;
let carol;

// Give a user N fresh cards (each a different blind-pack design) by activating admin-made physical cards.
async function giveCards(user, n, rarity = 'normal') {
  const cards = [];
  for (let i = 0; i < n; i++) {
    const pack = await s.call('POST', '/admin/blind-packs', { name: `ชุด ${user.username} ${i}`, rarity, count: 1, card_image: TINY_JPEG }, adm.token);
    const codes = (await s.call('GET', `/admin/blind-packs/${pack.body.template_id}/codes`, undefined, adm.token)).body.codes;
    cards.push((await s.call('POST', '/cards/activate', { payload: codes[0].payload }, user.token)).body.card);
  }
  return cards;
}
const status = async (user, cardId) => (await s.call('GET', '/cards', undefined, user.token)).body.cards.find((c) => c.card_instance_id === cardId)?.activation_status;
const owns = async (user, cardId) => !!(await s.call('GET', '/cards', undefined, user.token)).body.cards.find((c) => c.card_instance_id === cardId);

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  alice = await s.register('alice');
  bob = await s.register('bob');
  carol = await s.register('carol');
});
test.after(() => s.stop());

test('user search finds people by username and exposes nothing else', async () => {
  assert.equal((await s.call('GET', '/users/search?q=bo')).status, 401);
  const r = await s.call('GET', `/users/search?q=${bob.username.slice(0, 6)}`, undefined, alice.token);
  assert.ok(r.body.users.some((u) => u.username === bob.username));
  assert.deepEqual(Object.keys(r.body.users[0]).sort(), ['name', 'user_id', 'username']);
  assert.equal(r.body.users.some((u) => u.username === alice.username), false, 'not yourself');
  assert.equal(JSON.stringify(r.body).includes('@x.com'), false);
  assert.equal((await s.call('GET', '/users/search?q=a', undefined, alice.token)).body.users.length, 0, 'too short');
  assert.equal((await s.call('GET', '/users/search?q=admin', undefined, alice.token)).body.users.length, 0, 'admins are not searchable');
  assert.equal((await s.call('GET', '/users/search?q=%25%25', undefined, alice.token)).body.users.length, 0, 'wildcards are escaped');
});

test('offer validation: self, unknown recipient, cards you do not own, bad mode', async () => {
  const [a1] = await giveCards(alice, 1);
  const [b1] = await giveCards(bob, 1);
  const offer = (o, token = alice.token) => s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: a1.card_instance_id, ...o }, token);
  assert.equal((await offer({}, null)).status, 401);
  assert.equal((await offer({ mode: 'sell' })).status, 400);
  assert.equal((await offer({ to_username: alice.username })).status, 400);
  assert.equal((await offer({ to_username: 'nobody-here' })).status, 404);
  assert.equal((await offer({ offered_card_id: b1.card_instance_id })).status, 404, "cannot offer someone else's card");
  assert.equal((await offer({ offered_card_id: 'nope' })).status, 404);
  assert.equal((await offer({ mode: 'swap', requested_card_id: a1.card_instance_id })).status, 404, 'requested card must belong to the recipient');
  assert.equal((await offer({ mode: 'swap' })).status, 404, 'a swap needs a requested card');
});

test('gift: offer locks the card, notifies, accept moves ownership, logs it, notifies the sender', async () => {
  const [card] = await giveCards(alice, 1, 'rare');
  const o = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: card.card_instance_id }, alice.token);
  assert.equal(o.status, 201);
  const tradeId = o.body.trade.trade_id;
  assert.equal(await status(alice, card.card_instance_id), 'LOCKED_IN_TRADE');

  const n = (await s.call('GET', '/notifications', undefined, bob.token)).body.notifications.find((x) => x.type === 'trade_offer');
  assert.equal(n.data.trade_id, tradeId);

  const incoming = (await s.call('GET', '/trades', undefined, bob.token)).body.incoming;
  assert.equal(incoming.length >= 1, true);
  assert.equal(incoming.find((t) => t.trade_id === tradeId).offered_card.serial_label, '#001/1');

  assert.equal((await s.call('POST', `/trades/${tradeId}/accept`, {}, alice.token)).status, 404, 'the sender cannot accept');
  assert.equal((await s.call('POST', `/trades/${tradeId}/accept`, {}, carol.token)).status, 404, 'a third party cannot accept');
  const acc = await s.call('POST', `/trades/${tradeId}/accept`, {}, bob.token);
  assert.equal(acc.status, 200);
  assert.equal(acc.body.trade.status, 'accepted');

  assert.equal(await owns(alice, card.card_instance_id), false);
  assert.equal(await status(bob, card.card_instance_id), 'CLAIMED');
  assert.equal((await s.call('POST', `/trades/${tradeId}/accept`, {}, bob.token)).status, 409, 'cannot accept twice');
  assert.equal((await s.call('GET', '/notifications', undefined, alice.token)).body.notifications.some((x) => x.type === 'trade_accepted'), true);

  const db = s.sql();
  const log = db.prepare('SELECT from_user_id, to_user_id, reason, trade_id FROM card_ownership_log WHERE card_instance_id = ? ORDER BY created_at, rowid').all(card.card_instance_id);
  db.close();
  assert.deepEqual(log.map((l) => l.reason), ['activation', 'gift']);
  assert.equal(log[1].from_user_id, alice.id);
  assert.equal(log[1].to_user_id, bob.id);
  assert.equal(log[1].trade_id, tradeId);
});

test('swap exchanges both cards and logs both moves', async () => {
  const [a] = await giveCards(alice, 1);
  const [b] = await giveCards(bob, 1);
  const o = await s.call('POST', '/trades', { mode: 'swap', to_username: bob.username, offered_card_id: a.card_instance_id, requested_card_id: b.card_instance_id }, alice.token);
  assert.equal(o.status, 201);
  assert.equal(await status(alice, a.card_instance_id), 'LOCKED_IN_TRADE');
  assert.equal(await status(bob, b.card_instance_id), 'CLAIMED', 'the requested card is not locked until accepted');
  assert.equal((await s.call('POST', `/trades/${o.body.trade.trade_id}/accept`, {}, bob.token)).status, 200);
  assert.equal(await owns(bob, a.card_instance_id), true);
  assert.equal(await owns(alice, b.card_instance_id), true);
  assert.equal(await status(alice, b.card_instance_id), 'CLAIMED');
  const db = s.sql();
  const n = db.prepare("SELECT COUNT(*) AS c FROM card_ownership_log WHERE trade_id = ? AND reason = 'trade'").get(o.body.trade.trade_id).c;
  db.close();
  assert.equal(n, 2);
});

test('a locked card cannot be offered twice; reject and cancel unlock it', async () => {
  const [card] = await giveCards(alice, 1);
  const first = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: card.card_instance_id }, alice.token);
  const second = await s.call('POST', '/trades', { mode: 'gift', to_username: carol.username, offered_card_id: card.card_instance_id }, alice.token);
  assert.equal(second.status, 409);

  assert.equal((await s.call('POST', `/trades/${first.body.trade.trade_id}/cancel`, {}, bob.token)).status, 404, 'only the sender cancels');
  assert.equal((await s.call('POST', `/trades/${first.body.trade.trade_id}/reject`, {}, bob.token)).status, 200);
  assert.equal(await status(alice, card.card_instance_id), 'CLAIMED');
  assert.equal((await s.call('GET', '/notifications', undefined, alice.token)).body.notifications.some((x) => x.type === 'trade_rejected'), true);

  const again = await s.call('POST', '/trades', { mode: 'gift', to_username: carol.username, offered_card_id: card.card_instance_id }, alice.token);
  assert.equal(again.status, 201);
  assert.equal((await s.call('POST', `/trades/${again.body.trade.trade_id}/cancel`, {}, alice.token)).status, 200);
  assert.equal(await status(alice, card.card_instance_id), 'CLAIMED');
  assert.equal((await s.call('POST', `/trades/${again.body.trade.trade_id}/accept`, {}, carol.token)).status, 409, 'a cancelled offer cannot be accepted');
  const history = (await s.call('GET', '/trades', undefined, alice.token)).body.history.map((t) => t.status);
  assert.ok(history.includes('rejected') && history.includes('cancelled'));
});

test('pending offers expire after 48h and unlock the card', async () => {
  const [card] = await giveCards(alice, 1);
  const o = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: card.card_instance_id }, alice.token);
  const db = s.sql();
  db.prepare('UPDATE trades SET expires_at = ? WHERE trade_id = ?').run(new Date(Date.now() - 1000).toISOString(), o.body.trade.trade_id);
  db.close();
  const list = await s.call('GET', '/trades', undefined, alice.token);
  assert.equal(list.body.outgoing.some((t) => t.trade_id === o.body.trade.trade_id), false);
  assert.equal(list.body.history.find((t) => t.trade_id === o.body.trade.trade_id).status, 'expired');
  assert.equal(await status(alice, card.card_instance_id), 'CLAIMED');
  assert.equal((await s.call('POST', `/trades/${o.body.trade.trade_id}/accept`, {}, bob.token)).status, 409);
  assert.equal((await s.call('GET', '/notifications', undefined, alice.token)).body.notifications.some((x) => x.type === 'trade_expired'), true);
});

test('accept re-checks both cards: the requested card moved or got locked elsewhere', async () => {
  const [a] = await giveCards(alice, 1);
  const [b] = await giveCards(bob, 1);
  const o = await s.call('POST', '/trades', { mode: 'swap', to_username: bob.username, offered_card_id: a.card_instance_id, requested_card_id: b.card_instance_id }, alice.token);
  // Bob offers the requested card to Carol first, so it is locked in another trade
  const other = await s.call('POST', '/trades', { mode: 'gift', to_username: carol.username, offered_card_id: b.card_instance_id }, bob.token);
  assert.equal(other.status, 201);
  const fail = await s.call('POST', `/trades/${o.body.trade.trade_id}/accept`, {}, bob.token);
  assert.equal(fail.status, 409);
  assert.match(fail.body.error, /ข้อเสนอแลกเปลี่ยนอื่น/);
  assert.equal(await owns(alice, a.card_instance_id), true, 'nothing moved');
  assert.equal(await status(alice, a.card_instance_id), 'LOCKED_IN_TRADE', 'still pending, can be rejected or cancelled');
  assert.equal((await s.call('POST', `/trades/${o.body.trade.trade_id}/cancel`, {}, alice.token)).status, 200);
  assert.equal(await status(alice, a.card_instance_id), 'CLAIMED');
});

test('two simultaneous accepts of one offer: exactly one succeeds', async () => {
  const [card] = await giveCards(alice, 1);
  const o = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: card.card_instance_id }, alice.token);
  const results = await Promise.all([1, 2, 3].map(() => s.call('POST', `/trades/${o.body.trade.trade_id}/accept`, {}, bob.token)));
  assert.equal(results.filter((r) => r.status === 200).length, 1);
  assert.equal(await owns(bob, card.card_instance_id), true);
  const db = s.sql();
  assert.equal(db.prepare("SELECT COUNT(*) AS c FROM card_ownership_log WHERE trade_id = ?").get(o.body.trade.trade_id).c, 1);
  db.close();
});

test('a card that is not CLAIMED (unclaimed physical card) cannot be traded', async () => {
  const pack = await s.call('POST', '/admin/blind-packs', { name: 'x', rarity: 'normal', count: 1 }, adm.token);
  const db = s.sql();
  const card = db.prepare('SELECT card_instance_id FROM all_cards WHERE template_id = ?').get(pack.body.template_id);
  db.close();
  const r = await s.call('POST', '/trades', { mode: 'gift', to_username: bob.username, offered_card_id: card.card_instance_id }, alice.token);
  assert.equal(r.status, 404);
});

test("a traveler's tradable cards can be listed, without locked cards or private data", async () => {
  const [card, locked] = await giveCards(carol, 2);
  await s.call('POST', '/trades', { mode: 'gift', to_username: alice.username, offered_card_id: locked.card_instance_id }, carol.token);
  const r = await s.call('GET', `/users/${carol.username}/cards`, undefined, alice.token);
  assert.equal(r.status, 200);
  const ids = r.body.cards.map((c) => c.card_instance_id);
  assert.ok(ids.includes(card.card_instance_id));
  assert.equal(ids.includes(locked.card_instance_id), false);
  assert.equal(JSON.stringify(r.body).includes('base64'), false);
  assert.equal((await s.call('GET', `/users/${carol.username}/cards`)).status, 401);
  assert.equal((await s.call('GET', '/users/admin/cards', undefined, alice.token)).status, 404);
});
