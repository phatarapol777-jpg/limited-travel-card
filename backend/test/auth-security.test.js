const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
});
test.after(() => s.stop());

const login = (username, password) => s.call('POST', '/auth/login', { username, password });

async function giveCard(user, name = 'การ์ด') {
  const pack = await s.call('POST', '/admin/blind-packs', { name, rarity: 'normal', count: 1, card_image: TINY_JPEG }, adm.token);
  const codes = (await s.call('GET', `/admin/blind-packs/${pack.body.template_id}/codes`, undefined, adm.token)).body.codes;
  return (await s.call('POST', '/cards/activate', { payload: codes[0].payload }, user.token)).body.card;
}

test('health carries a version string', async () => {
  const r = await s.call('GET', '/health');
  assert.equal(r.body.ok, true);
  assert.equal(typeof r.body.version, 'string');
});

test('change password: validation, effect, and other sessions end while this one stays', async () => {
  const u = await s.register('pw');
  const second = (await login(u.username, 'secret123')).body.token;
  const change = (body, token = u.token) => s.call('POST', '/auth/change-password', body, token);

  assert.equal((await change({ current_password: 'secret123', new_password: 'x' }, null)).status, 401);
  assert.equal((await change({ current_password: 'secret123', new_password: 'short' })).status, 400, 'min 8 characters');
  assert.equal((await change({ current_password: 'wrong-one', new_password: 'longenough1' })).status, 400);
  assert.equal((await change({ current_password: 'secret123', new_password: 'secret123' })).status, 400, 'must differ');
  assert.equal((await change({ current_password: 'secret123', new_password: 'a'.repeat(201) })).status, 400);

  assert.equal((await change({ current_password: 'secret123', new_password: 'brand-new-pass' })).status, 200);
  assert.equal((await login(u.username, 'secret123')).status, 401, 'old password is dead');
  assert.equal((await login(u.username, 'brand-new-pass')).status, 200);
  assert.equal((await s.call('GET', '/auth/me', undefined, u.token)).status, 200, 'the session that changed it stays');
  assert.equal((await s.call('GET', '/auth/me', undefined, second)).status, 401, 'the other session ended');
});

test('logout ends the session on the server', async () => {
  const u = await s.register('out');
  assert.equal((await s.call('POST', '/auth/logout', {}, u.token)).status, 200);
  assert.equal((await s.call('GET', '/auth/me', undefined, u.token)).status, 401);
  assert.equal((await s.call('POST', '/auth/logout', {})).status, 401);
});

test('sessions expire after 30 days', async () => {
  const u = await s.register('old');
  const db = s.sql();
  db.prepare('UPDATE sessions SET created_at = ? WHERE token = ?').run(new Date(Date.now() - 31 * 86400000).toISOString(), u.token);
  db.close();
  const r = await s.call('GET', '/auth/me', undefined, u.token);
  assert.equal(r.status, 401);
  assert.match(r.body.error, /expired/i);
  const check = s.sql();
  assert.equal(check.prepare('SELECT COUNT(*) AS c FROM sessions WHERE token = ?').get(u.token).c, 0, 'the row is removed');
  check.close();
});

test('only admins are told about the default password, and it clears once changed', async () => {
  const u = await s.register('plain');
  assert.equal((await s.call('GET', '/auth/me', undefined, u.token)).body.user.using_default_password, undefined);
  assert.equal((await s.call('GET', '/auth/me', undefined, adm.token)).body.user.using_default_password, true);
  assert.equal((await s.call('POST', '/auth/change-password', { current_password: 'admin1234', new_password: 'a-new-admin-pass' }, adm.token)).status, 200);
  assert.equal((await s.call('GET', '/auth/me', undefined, adm.token)).body.user.using_default_password, false);
});

test('delete account: needs the username typed, is refused for admins, and anonymises everything', async () => {
  const gone = await s.register('leaving');
  const friend = await s.register('friend');
  const myCard = await giveCard(gone, 'ของฉัน');
  const friendCard = await giveCard(friend, 'ของเพื่อน');
  const pinned = await giveCard(gone, 'ปักหมุด');
  await s.call('PUT', '/profile/pins', { card_instance_ids: [pinned.card_instance_id] }, gone.token);

  // one offer from the leaver, one offer to the leaver, one post, one quest
  const out = await s.call('POST', '/trades', { mode: 'gift', to_username: friend.username, offered_card_id: myCard.card_instance_id }, gone.token);
  const into = await s.call('POST', '/trades', { mode: 'swap', to_username: gone.username, offered_card_id: friendCard.card_instance_id, requested_card_id: pinned.card_instance_id }, friend.token);
  assert.equal(out.status, 201);
  assert.equal(into.status, 201);
  const post = await s.call('POST', '/community/posts', { content: 'โพสต์ของคนที่จะลบบัญชี' }, gone.token);
  assert.equal(post.status, 201);
  const loc = (await s.call('GET', '/catalog/locations')).body.locations[0].location_id;
  const quest = await s.call('POST', '/quests', {
    title: 'q', location_id: loc, description: 'd', cover_image: TINY_JPEG, permanent: true, card_name: 'c', card_image: TINY_JPEG, rarity: 'normal', mint_limit: 5,
  }, gone.token);
  assert.equal(quest.status, 201);

  assert.equal((await s.call('POST', '/auth/delete-account', { confirm_username: 'nope' }, gone.token)).status, 400);
  assert.equal((await s.call('POST', '/auth/delete-account', {}, gone.token)).status, 400);
  assert.equal((await s.call('POST', '/auth/delete-account', { confirm_username: 'admin' }, adm.token)).status, 403);
  assert.equal((await s.call('POST', '/auth/delete-account', { confirm_username: gone.username })).status, 401);

  assert.equal((await s.call('POST', '/auth/delete-account', { confirm_username: gone.username }, gone.token)).status, 200);

  assert.equal((await s.call('GET', '/auth/me', undefined, gone.token)).status, 401, 'sessions are gone');
  assert.equal((await login(gone.username, 'secret123')).status, 401, 'cannot sign in any more');
  assert.equal((await s.call('GET', `/profile/${gone.username}`, undefined, friend.token)).status, 404);

  const db = s.sql();
  const row = db.prepare('SELECT * FROM users WHERE user_id = ?').get(gone.id);
  assert.match(row.username, /^deleted-/);
  assert.match(row.email, /^deleted-.*@invalid\.local$/);
  assert.equal(row.phone, null);
  assert.equal(row.face_descriptor, null);
  assert.equal(row.google_sub, null);
  assert.equal(row.face_photo, null);
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM user_pins WHERE user_id = ?').get(gone.id).c, 0);
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM notifications WHERE user_id = ?').get(gone.id).c, 0);
  assert.equal(db.prepare('SELECT status FROM community_posts WHERE post_id = ?').get(post.body.post_id).status, 'hidden');
  assert.equal(db.prepare('SELECT status FROM quests WHERE quest_id = ?').get(quest.body.quest_id).status, 'closed');
  assert.equal(db.prepare("SELECT COUNT(*) AS c FROM trades WHERE status = 'pending' AND (from_user_id = ? OR to_user_id = ?)").get(gone.id, gone.id).c, 0);
  assert.equal(db.prepare('SELECT owner_user_id FROM all_cards WHERE card_instance_id = ?').get(myCard.card_instance_id).owner_user_id, gone.id, 'history keeps pointing at the anonymous row');
  db.close();

  // the friend's card that was offered to the leaver is unlocked again, and the friend was told
  const mine = (await s.call('GET', '/cards', undefined, friend.token)).body.cards.find((c) => c.card_instance_id === friendCard.card_instance_id);
  assert.equal(mine.activation_status, 'CLAIMED');
  const notes = (await s.call('GET', '/notifications', undefined, friend.token)).body.notifications;
  assert.ok(notes.some((n) => n.type === 'trade_cancelled' && /ลบบัญชี/.test(n.text)));
  const posts = (await s.call('GET', '/community/posts')).body.posts;
  assert.equal(posts.some((p) => p.post_id === post.body.post_id), false, 'the post is no longer public');
});

test('settings: admin-only, validated, and stored', async () => {
  const u = await s.register('settinguser');
  assert.equal((await s.call('GET', '/admin/settings', undefined, u.token)).status, 403);
  const list = (await s.call('GET', '/admin/settings', undefined, adm.token)).body.settings;
  assert.deepEqual(list.map((x) => x.key).sort(), ['community_badge_top_n', 'community_tag_verify', 'env_check', 'kiosk_geo_radius_m', 'quest_geo_check', 'quest_geo_radius_m']);
  assert.equal(list.find((x) => x.key === 'quest_geo_radius_m').value, 1000);

  assert.equal((await s.call('PUT', '/admin/settings', { quest_geo_check: false, quest_geo_radius_m: 750 }, adm.token)).status, 200);
  const after = (await s.call('GET', '/admin/settings', undefined, adm.token)).body.settings;
  assert.equal(after.find((x) => x.key === 'quest_geo_check').value, false);
  assert.equal(after.find((x) => x.key === 'quest_geo_radius_m').value, 750);
  assert.equal(after.find((x) => x.key === 'quest_geo_radius_m').changed, true);

  for (const bad of [{ quest_geo_check: 'yes' }, { quest_geo_radius_m: 5 }, { quest_geo_radius_m: 1.5 }, { quest_geo_radius_m: 'abc' }, { nope: true }, { env_check: 1 }]) {
    assert.equal((await s.call('PUT', '/admin/settings', bad, adm.token)).status, 400, JSON.stringify(bad));
  }
});

test('backup status is admin-only and says the safety net is off in tests', async () => {
  const u = await s.register('bk');
  assert.equal((await s.call('GET', '/admin/backup-status', undefined, u.token)).status, 403);
  const st = (await s.call('GET', '/admin/backup-status', undefined, adm.token)).body;
  assert.equal(st.enabled, false);
  assert.equal(st.lastSuccessAt, null);
});
