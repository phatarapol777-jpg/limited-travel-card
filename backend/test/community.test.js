const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let ann;
let ben;
let cat;
let locId;
let locId2;

const img = (n = 1) => Array.from({ length: n }, () => ({ image: TINY_JPEG }));
const bigJpeg = (chars) => `data:image/jpeg;base64,${Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(Math.floor((chars / 4) * 3) - 4, 7)]).toString('base64')}`;
const post = (body, u = ann) => s.call('POST', '/community/posts', body, u.token);
const feed = (query = '', u) => s.call('GET', `/community/posts${query}`, undefined, u && u.token);
const notices = async (u, type) => (await s.call('GET', '/notifications', undefined, u.token)).body.notifications.filter((n) => !type || n.type === type);

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  ann = await s.register('ann');
  ben = await s.register('ben');
  cat = await s.register('cat');
  const locs = (await s.call('GET', '/catalog/locations')).body.locations;
  locId = locs[0].location_id;
  locId2 = locs[1].location_id;
});
test.after(() => s.stop());

test('posting: text, pictures, a place tag and hashtags; validation and sign-in', async () => {
  assert.equal((await s.call('POST', '/community/posts', { content: 'hi' })).status, 401);
  for (const bad of [{}, { content: '   ' }, { content: 'x'.repeat(2001) }, { content: 'x', images: img(11) }, { content: 'x', images: [{ image: 'nope' }] },
    { content: 'x', images: [{ image: bigJpeg(50_000) }] }, { content: 'x', location_id: 'does-not-exist' }]) {
    assert.equal((await post(bad)).status, 400, JSON.stringify(bad).slice(0, 80));
  }
  const ok = await post({ content: 'เที่ยวดอยสุเทพ #ดอยสุเทพ #Chiang_Mai สวยมาก', images: img(10), location_id: locId });
  assert.equal(ok.status, 201);
  const v = (await s.call('GET', `/community/posts/${ok.body.post_id}`)).body.post;
  assert.equal(v.images.length, 10);
  assert.equal(v.location.location_id, locId);
  assert.deepEqual([...v.hashtags].sort(), ['chiang_mai', 'ดอยสุเทพ']);
  assert.equal(JSON.stringify(v).includes('base64'), false, 'pictures are served by id, never inlined');
  assert.equal((await post({ images: img(1) })).status, 201, 'a picture alone is enough');
});

test('people are shown by display name only: no email, phone or real name anywhere', async () => {
  const p = (await feed('?limit=5')).body.posts[0];
  const text = JSON.stringify(p);
  assert.ok(p.author.display_name);
  for (const secret of ['@x.com', 'first_name', 'last_name', 'email', 'phone', 'password']) assert.equal(text.includes(secret), false, secret);
});

test('feed: newest first with a cursor, filters by tag, user, place and text (wildcards are literal)', async () => {
  const db = s.sql();
  const ins = db.prepare("INSERT INTO community_posts (post_id, user_id, content, status, timestamp, updated_at) VALUES (?, ?, ?, 'visible', ?, ?)");
  for (let i = 0; i < 45; i++) {
    const t = new Date(Date.now() - (2 * 24 * 60 + i) * 60000).toISOString(); // two days back, so they do not use up the daily limit
    ins.run(`bulk${String(i).padStart(2, '0')}`, ben.id, i === 7 ? 'ส่วนลด 100% ที่นี่' : `โพสต์ที่ ${i}`, t, t);
  }
  db.close();
  const first = (await feed('?limit=20')).body;
  assert.equal(first.posts.length, 20);
  assert.ok(first.next);
  const second = (await feed(`?limit=20&before=${encodeURIComponent(first.next)}`)).body;
  const third = (await feed(`?limit=20&before=${encodeURIComponent(second.next)}`)).body;
  const ids = [...first.posts, ...second.posts, ...third.posts].map((x) => x.post_id);
  assert.equal(new Set(ids).size, ids.length, 'no post appears on two pages');
  assert.ok(ids.length >= 47, 'the 45 bulk posts, the two test posts and whatever the seed added');
  assert.equal(third.next, null);

  assert.equal((await feed('?tag=ดอยสุเทพ')).body.posts.length, 1);
  assert.equal((await feed('?tag=%23chiang_mai')).body.posts.length, 1, 'a leading # is accepted');
  assert.equal((await feed(`?user=${ben.username}&limit=50`)).body.posts.length, 45);
  assert.equal((await feed(`?location=${locId}`)).body.posts.length, 1);
  assert.equal((await feed('?q=100%25')).body.posts.length, 1, '% matches only the literal percent sign');
  assert.equal((await feed(`?q=${encodeURIComponent('โพ_ต์')}`)).body.posts.length, 0, '_ is not a one-letter wildcard');
});

test('feed tabs: following needs sign-in and only shows followed people; trending ranks by recent reactions and comments', async () => {
  assert.equal((await feed('?tab=following')).status, 401);
  assert.equal((await feed('?tab=following', cat)).body.posts.length, 0, 'follows nobody yet');
  assert.equal((await s.call('POST', `/community/users/${ben.username}/follow`, {}, cat.token)).status, 200);
  assert.equal((await feed('?tab=following&limit=50', cat)).body.posts.length, 45);
  assert.ok((await feed('?tab=following&limit=50', cat)).body.posts.every((p) => p.author.username === ben.username));

  // trending: a day-old post with two reactions and a comment beats the rest of a quiet field
  const quiet = (await feed('?limit=1')).body.posts[0];
  const hot = await post({ content: 'โพสต์ยอดนิยม' }, ben);
  await s.call('PUT', `/community/posts/${hot.body.post_id}/reaction`, { type: 'LOVE' }, ann.token);
  await s.call('PUT', `/community/posts/${hot.body.post_id}/reaction`, { type: 'WOW' }, cat.token);
  await s.call('POST', `/community/posts/${hot.body.post_id}/comments`, { content: 'เจ๋ง' }, ann.token);
  const trending = (await feed('?tab=trending&limit=3')).body.posts;
  assert.equal(trending[0].post_id, hot.body.post_id);
  assert.notEqual(quiet.post_id, hot.body.post_id);
});

let mine;
test('editing and deleting: only the owner, pictures kept or replaced, hashtags follow the text', async () => {
  mine = (await post({ content: 'ต้นฉบับ #เก่า', images: img(3), location_id: locId })).body.post_id;
  const before = (await s.call('GET', `/community/posts/${mine}`)).body.post.images;

  assert.equal((await s.call('PUT', `/community/posts/${mine}`, { content: 'แก้' }, ben.token)).status, 404);
  assert.equal((await s.call('DELETE', `/community/posts/${mine}`, undefined, ben.token)).status, 404);
  assert.equal((await s.call('PUT', `/community/posts/${mine}`, { content: '' , images: [] }, ann.token)).status, 400, 'cannot end up empty');
  assert.equal((await s.call('PUT', `/community/posts/${mine}`, { content: 'x', images: [{ image_id: 'pim-someone-elses' }] }, ann.token)).status, 400);

  const edit = await s.call('PUT', `/community/posts/${mine}`, { content: 'ฉบับแก้ #ใหม่', images: [{ image_id: before[2] }, { image: TINY_JPEG }], location_id: locId2 }, ann.token);
  assert.equal(edit.status, 200);
  const after = (await s.call('GET', `/community/posts/${mine}`)).body.post;
  assert.equal(after.images.length, 2);
  assert.equal(after.images[0], before[2], 'a kept picture keeps its id and moves to its new position');
  assert.ok(!before.slice(0, 2).some((id) => after.images.includes(id)), 'dropped pictures are gone');
  assert.deepEqual(after.hashtags, ['ใหม่']);
  assert.equal(after.location.location_id, locId2);
  assert.ok(after.updated_at);
  assert.equal((await s.call('GET', `/media/post-image/${before[0]}`)).status, 404);

  const keep = await s.call('PUT', `/community/posts/${mine}`, { content: 'แก้เฉพาะข้อความ' }, ann.token);
  assert.equal(keep.status, 200);
  const unchanged = (await s.call('GET', `/community/posts/${mine}`)).body.post;
  assert.equal(unchanged.images.length, 2, 'leaving images out keeps them');
  assert.equal(unchanged.location.location_id, locId2);
  const unTagged = await s.call('PUT', `/community/posts/${mine}`, { content: 'ไม่มีแท็ก', location_id: null }, ann.token);
  assert.equal(unTagged.status, 200);
  assert.equal((await s.call('GET', `/community/posts/${mine}`)).body.post.location, null);

  const gone = (await post({ content: 'จะลบ', images: img(2) })).body.post_id;
  await s.call('PUT', `/community/posts/${gone}/reaction`, { type: 'LIKE' }, ben.token);
  await s.call('POST', `/community/posts/${gone}/comments`, { content: 'c' }, ben.token);
  assert.equal((await s.call('DELETE', `/community/posts/${gone}`, undefined, ann.token)).status, 200);
  assert.equal((await s.call('GET', `/community/posts/${gone}`)).status, 404);
  const db = s.sql();
  for (const t of ['post_images', 'post_reactions', 'community_comments', 'post_hashtags']) assert.equal(db.prepare(`SELECT COUNT(*) AS c FROM ${t} WHERE post_id = ?`).get(gone).c, 0, t);
  db.close();
});

test('reactions: five kinds, switch or remove, one notice per person per post, none for your own post', async () => {
  const id = (await post({ content: 'ทดสอบรีแอคชัน' })).body.post_id;
  assert.equal((await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'HAHA' }, ben.token)).status, 400);
  assert.equal((await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'LIKE' })).status, 401);
  let r = (await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'LOVE' }, ben.token)).body;
  assert.deepEqual([r.my_reaction, r.reaction_count, r.reactions.LOVE], ['LOVE', 1, 1]);
  r = (await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'ANGRY' }, ben.token)).body;
  assert.deepEqual([r.my_reaction, r.reaction_count, r.reactions.LOVE, r.reactions.ANGRY], ['ANGRY', 1, undefined, 1], 'switching replaces, it does not add');
  await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'SAD' }, cat.token);
  r = (await s.call('DELETE', `/community/posts/${id}/reaction`, undefined, ben.token)).body;
  assert.deepEqual([r.my_reaction, r.reaction_count], [null, 1]);
  await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'WOW' }, ben.token); // gives it again after taking it back
  await s.call('PUT', `/community/posts/${id}/reaction`, { type: 'LIKE' }, ann.token); // own post
  const mineNotices = (await notices(ann, 'community_reaction')).filter((n) => (n.data || {}).post_id === id);
  assert.equal(mineNotices.length, 2, 'ben once and cat once, never ann herself, never twice for ben');

  const seen = (await feed('?limit=3', ben)).body.posts.find((p) => p.post_id === id);
  assert.equal(seen.my_reaction, 'WOW');
  const legacy = await s.call('POST', `/community/posts/${id}/like`, {}, cat.token);
  assert.equal(legacy.body.liked, false, 'the old like button toggles the existing reaction off');
});

test('comments: text and a picture, own edit and delete only, notice to the author', async () => {
  const id = (await post({ content: 'ทดสอบคอมเมนต์' })).body.post_id;
  assert.equal((await s.call('POST', `/community/posts/${id}/comments`, { content: 'x' })).status, 401);
  for (const bad of [{}, { content: ' ' }, { content: 'x'.repeat(1001) }, { image: 'nope' }, { content: 'x', image: bigJpeg(40_000) }]) {
    assert.equal((await s.call('POST', `/community/posts/${id}/comments`, bad, ben.token)).status, 400, JSON.stringify(bad).slice(0, 60));
  }
  const c = (await s.call('POST', `/community/posts/${id}/comments`, { content: 'สวยจัง', image: TINY_JPEG }, ben.token)).body.comment_id;
  const list = (await s.call('GET', `/community/posts/${id}/comments`, undefined, ben.token)).body.comments;
  assert.equal(list.length, 1);
  assert.equal(list[0].has_image, true);
  assert.equal(list[0].is_mine, true);
  assert.equal(list[0].author.display_name, ben.username);
  assert.equal((await s.call('GET', `/media/comment-image/${c}`)).res.headers.get('content-type'), 'image/jpeg');
  assert.equal((await s.call('GET', `/community/posts/${id}/comments`)).body.comments[0].is_mine, false);

  assert.equal((await s.call('PUT', `/community/comments/${c}`, { content: 'แก้' }, cat.token)).status, 404);
  assert.equal((await s.call('DELETE', `/community/comments/${c}`, undefined, cat.token)).status, 404);
  assert.equal((await s.call('DELETE', `/community/comments/${c}`, undefined, ann.token)).status, 404, 'even the post owner cannot edit or delete another person\'s comment here');
  assert.equal((await s.call('PUT', `/community/comments/${c}`, { content: 'แก้แล้ว' }, ben.token)).status, 200);
  const edited = (await s.call('GET', `/community/posts/${id}/comments`)).body.comments[0];
  assert.equal(edited.content, 'แก้แล้ว');
  assert.equal(edited.edited, true);
  assert.equal(edited.has_image, true, 'editing the text keeps the picture');
  assert.equal((await s.call('PUT', `/community/comments/${c}`, { content: 'ไม่มีรูป', image: null }, ben.token)).status, 200);
  assert.equal((await s.call('GET', `/community/posts/${id}/comments`)).body.comments[0].has_image, false);
  assert.equal((await s.call('PUT', `/community/comments/${c}`, { content: '', image: null }, ben.token)).status, 400, 'cannot end up empty');

  const note = (await notices(ann, 'community_comment')).find((n) => n.data.comment_id === c);
  assert.match(note.text, /สวยจัง/);
  await s.call('POST', `/community/posts/${id}/comments`, { content: 'ตอบตัวเอง' }, ann.token);
  assert.equal((await notices(ann, 'community_comment')).filter((n) => n.data.post_id === id).length, 1, 'no notice for commenting on your own post');
  assert.equal((await s.call('DELETE', `/community/comments/${c}`, undefined, ben.token)).status, 200);
  assert.equal((await feed('?limit=50')).body.posts.find((p) => p.post_id === id).comment_count, 1);
});

test('reports: one per person, not your own post, and admins see them with the reasons', async () => {
  const id = (await post({ content: 'โพสต์ที่ไม่เหมาะสม' }, cat)).body.post_id;
  assert.equal((await s.call('POST', `/community/posts/${id}/report`, { reason: 'สแปม' })).status, 401);
  assert.equal((await s.call('POST', `/community/posts/${id}/report`, { reason: 'สแปม' }, cat.token)).status, 400);
  assert.equal((await s.call('POST', `/community/posts/${id}/report`, {}, ann.token)).status, 400);
  assert.equal((await s.call('POST', `/community/posts/${id}/report`, { reason: 'สแปม' }, ann.token)).status, 201);
  assert.equal((await s.call('POST', `/community/posts/${id}/report`, { reason: 'สแปม' }, ann.token)).status, 409);
  await s.call('POST', `/community/posts/${id}/report`, { reason: 'คำหยาบ' }, ben.token);
  assert.equal((await feed('?limit=50', ann)).body.posts.find((p) => p.post_id === id).reported_by_me, true);
  assert.equal((await feed('?limit=50', cat)).body.posts.find((p) => p.post_id === id).reported_by_me, false);

  assert.equal((await s.call('GET', '/admin/community/posts?reported=1', undefined, ann.token)).status, 403);
  const list = (await s.call('GET', '/admin/community/posts?reported=1', undefined, adm.token)).body.posts;
  assert.deepEqual(list.map((p) => [p.post_id, p.reports]), [[id, 2]]);
  const reasons = (await s.call('GET', `/admin/community/posts/${id}/reports`, undefined, adm.token)).body.reports.map((r) => r.reason).sort();
  assert.deepEqual(reasons, ['คำหยาบ', 'สแปม']);
});

test('following: not yourself, one notice, counts, lists, unfollow', async () => {
  const dan = await s.register('dan');
  assert.equal((await s.call('POST', `/community/users/${dan.username}/follow`, {}, dan.token)).status, 400);
  assert.equal((await s.call('POST', '/community/users/nobody-here/follow', {}, dan.token)).status, 404);
  assert.equal((await s.call('POST', `/community/users/${dan.username}/follow`, {})).status, 401);
  await s.call('POST', `/community/users/${dan.username}/follow`, {}, ann.token);
  await s.call('POST', `/community/users/${dan.username}/follow`, {}, ann.token); // twice
  await s.call('DELETE', `/community/users/${dan.username}/follow`, undefined, ann.token);
  await s.call('POST', `/community/users/${dan.username}/follow`, {}, ann.token); // again after unfollow
  await s.call('POST', `/community/users/${dan.username}/follow`, {}, ben.token);
  assert.equal((await notices(dan, 'community_follow')).length, 2, 'ann once (however many times), and ben');
  const prof = (await s.call('GET', `/community/users/${dan.username}`, undefined, ann.token)).body.profile;
  assert.deepEqual([prof.stats.followers, prof.is_following, prof.is_me], [2, true, false]);
  assert.equal((await s.call('GET', `/community/users/${dan.username}/followers`)).body.users.length, 2);
  assert.equal((await s.call('GET', `/community/users/${ann.username}/following`)).body.users.some((u) => u.username === dan.username), true);
  const un = await s.call('DELETE', `/community/users/${dan.username}/follow`, undefined, ben.token);
  assert.deepEqual([un.body.is_following, un.body.followers], [false, 1]);
});

test('profile: display name, bio, pictures with caps, badge switch, public view', async () => {
  const bad = [{ display_name: 'x'.repeat(31) }, { bio: 'x'.repeat(201) }, { avatar: 'nope' }, { avatar: bigJpeg(30_000) }, { cover: bigJpeg(95_000) },
    { is_badge_visible: 'yes' }, { selected_badge_id: 'bdg-not-mine' }];
  for (const b of bad) assert.equal((await s.call('PUT', '/community/me', b, ann.token)).status, 400, JSON.stringify(b).slice(0, 60));
  assert.equal((await s.call('PUT', '/community/me', {})).status, 401);

  const before = (await s.call('GET', '/community/me', undefined, ann.token)).body.profile;
  const r = await s.call('PUT', '/community/me', { display_name: 'แอนนักเดินทาง', bio: 'ชอบเที่ยวภูเขา', avatar: TINY_JPEG, cover: TINY_JPEG }, ann.token);
  assert.equal(r.status, 200);
  assert.deepEqual([r.body.profile.display_name, r.body.profile.bio, r.body.profile.has_avatar, r.body.profile.has_cover], ['แอนนักเดินทาง', 'ชอบเที่ยวภูเขา', true, true]);
  assert.equal(r.body.profile.avatar_rev, before.avatar_rev + 1, 'a new picture changes the version so caches refresh');
  assert.equal((await s.call('GET', `/media/avatar/${ann.username}`)).status, 200);
  assert.equal((await s.call('GET', `/media/cover/${ann.username}`)).status, 200);

  const pub = (await s.call('GET', `/community/users/${ann.username}`)).body.profile;
  assert.equal(pub.display_name, 'แอนนักเดินทาง');
  assert.deepEqual(Object.keys(pub.stats).sort(), ['followers', 'following', 'places_checked_in', 'posts']);
  assert.equal(JSON.stringify(pub).includes('@x.com'), false);
  assert.equal((await feed('?limit=1', ben)).body.posts.length, 1);
  const shown = (await s.call('GET', `/community/posts/${mine}`)).body.post;
  assert.equal(shown.author.display_name, 'แอนนักเดินทาง', 'posts show the display name');

  await s.call('PUT', '/community/me', { avatar: null, display_name: '' }, ann.token);
  assert.equal((await s.call('GET', `/media/avatar/${ann.username}`)).status, 404);
  assert.equal((await s.call('GET', `/community/users/${ann.username}`)).body.profile.display_name, ann.username, 'empty name falls back to the username');

  assert.equal((await s.call('GET', '/community/users/admin')).status, 404, 'admin accounts are not public profiles');
  assert.equal((await s.call('GET', '/community/users/no-such-user')).status, 404);
});

test('badge: shown after the name only while its switch is on, and only a badge you own can be chosen', async () => {
  const db = s.sql();
  db.prepare("INSERT INTO user_badges (badge_id, user_id, awarded_month, rank_position, icon, title, created_at) VALUES ('bdg-1', ?, '2026-09', 1, 'gold', 'แชมป์', ?)").run(cat.id, new Date().toISOString());
  db.prepare("INSERT INTO user_badges (badge_id, user_id, awarded_month, rank_position, icon, title, created_at) VALUES ('bdg-2', ?, '2026-08', 2, 'silver', 'รองแชมป์', ?)").run(cat.id, new Date().toISOString());
  db.prepare("UPDATE users SET selected_badge_id = 'bdg-1' WHERE user_id = ?").run(cat.id);
  db.close();
  const id = (await post({ content: 'โพสต์ของคนมีตรา' }, cat)).body.post_id;
  const badgeOf = async () => (await s.call('GET', `/community/posts/${id}`)).body.post.author.badge;
  assert.equal((await badgeOf()).badge_id, 'bdg-1');
  await s.call('POST', `/community/posts/${id}/comments`, { content: 'คอมเมนต์ของฉัน' }, cat.token);
  assert.equal((await s.call('GET', `/community/posts/${id}/comments`)).body.comments[0].author.badge.icon, 'gold', 'comments show it too');

  await s.call('PUT', '/community/me', { is_badge_visible: false }, cat.token);
  assert.equal(await badgeOf(), null, 'switched off: hidden everywhere');
  assert.equal((await s.call('GET', `/community/posts/${id}/comments`)).body.comments[0].author.badge, null);
  assert.equal((await s.call('GET', `/community/users/${cat.username}`)).body.profile.badges.length, 2, 'the badges themselves are still listed on the profile');
  assert.equal((await s.call('PUT', '/community/me', { selected_badge_id: 'bdg-2', is_badge_visible: true }, cat.token)).status, 200);
  assert.equal((await badgeOf()).badge_id, 'bdg-2');
  assert.equal((await s.call('PUT', '/community/me', { selected_badge_id: 'bdg-1' }, ann.token)).status, 400, "someone else's badge");
});

test('search: users by name, hashtags by prefix, posts by text', async () => {
  await s.call('PUT', '/community/me', { display_name: 'นักปีนเขา' }, ben.token);
  await post({ content: 'ปีนเขา #ภูกระดึง #ภูผาม่าน' });
  const users = (await s.call('GET', `/community/search?q=${encodeURIComponent('ปีนเขา')}`)).body;
  assert.deepEqual(users.users.map((u) => u.username), [ben.username]);
  assert.ok(users.posts.length >= 1);
  const tags = (await s.call('GET', `/community/search?q=${encodeURIComponent('#ภูผ')}`)).body;
  assert.deepEqual(tags.tags.map((t) => t.tag), ['ภูผาม่าน']);
  assert.deepEqual((await s.call('GET', '/community/search?q=%23')).body, { users: [], tags: [], posts: [] });
  assert.deepEqual((await s.call('GET', '/community/search?q=')).body, { users: [], tags: [], posts: [] });
  assert.equal((await s.call('GET', '/community/search?q=%25')).body.users.length, 0, 'a lone % is not a wildcard');
});

test('place suggestions come from check-ins and bookings', async () => {
  assert.equal((await s.call('GET', '/community/suggestions')).status, 401);
  const u = await s.register('traveler');
  assert.deepEqual((await s.call('GET', '/community/suggestions', undefined, u.token)).body, { booked: [], checked_in: [] });
  const db = s.sql();
  db.pragma('foreign_keys = OFF');
  db.prepare("INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status) VALUES ('hh1', ?, ?, ?, 'success')").run(u.id, locId, new Date().toISOString());
  db.prepare("INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status) VALUES ('hh2', ?, ?, ?, 'failed')").run(u.id, locId2, new Date().toISOString());
  db.prepare("INSERT INTO hotels (hotel_id, external_hotel_id, name, city_code, location_id, cached_at) VALUES ('ht1', 'ext1', 'โรงแรม', 'X', ?, ?)").run(locId2, new Date().toISOString());
  db.prepare("INSERT INTO hotel_offers (offer_id, search_id, hotel_id, check_in_date, check_out_date, cached_at) VALUES ('of1', 'srch1', 'ht1', '2026-12-01', '2026-12-02', '2026-10-01')").run();
  db.prepare("INSERT INTO booking_requests (booking_request_id, user_id, offer_id, guest_name, status, requested_at) VALUES ('br1', ?, 'of1', 'g', 'confirmed', ?)").run(u.id, new Date().toISOString());
  db.close();
  const r = (await s.call('GET', '/community/suggestions', undefined, u.token)).body;
  assert.deepEqual(r.checked_in.map((x) => x.location_id), [locId], 'failed check-ins do not count');
  assert.deepEqual(r.booked.map((x) => [x.location_id, x.confirmed]), [[locId2, true]]);
});

test('pictures follow the post: hidden posts show nothing, admins see them, and daily limits apply', async () => {
  const id = (await post({ content: 'โพสต์ที่จะถูกซ่อน', images: img(1) })).body.post_id;
  const imageId = (await s.call('GET', `/community/posts/${id}`)).body.post.images[0];
  assert.equal((await s.call('GET', `/media/post-image/${imageId}`)).status, 200);
  assert.equal((await s.call('PUT', `/admin/community/posts/${id}`, { status: 'hidden' }, adm.token)).status, 200);
  assert.equal((await s.call('GET', `/media/post-image/${imageId}`)).status, 404);
  assert.equal((await s.call('GET', `/community/posts/${id}`)).status, 404);
  assert.equal((await s.call('GET', `/admin/community/posts/${id}/images`, undefined, adm.token)).body.images.length, 1);
  assert.equal((await s.call('PUT', `/community/posts/${id}`, { content: 'แก้' }, ann.token)).status, 404, 'a hidden post cannot be edited by its author');

  const u = await s.register('poster');
  let last;
  for (let i = 0; i < 21; i++) last = await post({ content: `ทดสอบ ${i}` }, u);
  assert.equal(last.status, 429);
  assert.match(last.body.error, /20/);
});

test('admin overview of the community, stats and tab data', async () => {
  const st = (await s.call('GET', '/admin/stats', undefined, adm.token)).body.modules.community;
  for (const k of ['posts', 'hidden_posts', 'comments', 'reactions', 'follows', 'reported_posts', 'badges_awarded']) assert.equal(typeof st[k], 'number', k);
  assert.ok(st.posts > 40);
  const list = (await s.call('GET', '/admin/community/posts', undefined, adm.token)).body.posts;
  assert.ok(list.length <= 100);
  assert.ok('reports' in list[0] && 'images' in list[0] && 'likes' in list[0]);
});

test('account deletion removes the person from the community', async () => {
  const gone = await s.register('leaver');
  await s.call('PUT', '/community/me', { display_name: 'จะลาก่อน', bio: 'bye', avatar: TINY_JPEG }, gone.token);
  const p = (await post({ content: 'โพสต์ก่อนลาก่อน', images: img(1), location_id: locId }, gone)).body.post_id;
  await s.call('POST', `/community/posts/${(await post({ content: 'ของคนอื่น' })).body.post_id}/comments`, { content: 'คอมเมนต์ก่อนไป' }, gone.token);
  await s.call('POST', `/community/users/${ann.username}/follow`, {}, gone.token);
  await s.call('POST', `/community/users/${gone.username}/follow`, {}, ann.token);
  assert.equal((await s.call('POST', '/auth/delete-account', { confirm_username: gone.username }, gone.token)).status, 200);

  assert.equal((await s.call('GET', `/community/posts/${p}`)).status, 404);
  assert.equal((await s.call('GET', `/community/users/${gone.username}`)).status, 404);
  const db = s.sql();
  const row = db.prepare('SELECT display_name, bio, avatar, cover FROM users WHERE user_id = ?').get(gone.id);
  assert.deepEqual(row, { display_name: null, bio: null, avatar: null, cover: null });
  for (const [sql, arg] of [['SELECT COUNT(*) AS c FROM follows WHERE follower_user_id = ? OR following_user_id = ?', [gone.id, gone.id]], ['SELECT COUNT(*) AS c FROM community_comments WHERE user_id = ?', [gone.id]],
    ['SELECT COUNT(*) AS c FROM post_images WHERE post_id = ?', [p]]]) assert.equal(db.prepare(sql).get(...arg).c, 0, sql);
  db.close();
});

test('old likes became LIKE reactions and old emoji posts still show', async () => {
  const db = s.sql();
  const t = new Date().toISOString();
  db.prepare("INSERT INTO community_posts (post_id, user_id, content, image_emoji, status, timestamp) VALUES ('legacy1', ?, 'โพสต์เก่า', '🛕', 'visible', ?)").run(ann.id, t);
  db.close();
  const v = (await s.call('GET', '/community/posts/legacy1')).body.post;
  assert.equal(v.image_emoji, '🛕');
  assert.deepEqual([v.images.length, v.comment_count, v.reaction_count], [0, 0, 0]);
});

test('the picture budget: new pictures are refused once the database is over its limit, text still works', async () => {
  const tight = await startServer({ COMMUNITY_DB_LIMIT_MB: '1' });
  try {
    const u = await tight.register('tight');
    assert.equal((await tight.call('POST', '/community/posts', { content: 'ยังโพสต์รูปได้', images: img(1) }, u.token)).status, 201);
    const db = tight.sql();
    db.prepare("INSERT INTO settings (key, value, updated_at) VALUES ('padding', ?, 'x')").run('x'.repeat(2 * 1024 * 1024));
    db.close();
    const refused = await tight.call('POST', '/community/posts', { content: 'มีรูป', images: img(1) }, u.token);
    assert.equal(refused.status, 507);
    assert.match(refused.body.error, /รูป/);
    assert.equal((await tight.call('POST', '/community/posts', { content: 'ข้อความล้วน' }, u.token)).status, 201);
    assert.equal((await tight.call('PUT', '/community/me', { avatar: TINY_JPEG }, u.token)).status, 507);
  } finally {
    tight.stop();
  }
});

test('the leaderboard endpoint is public and carries months, rows and my rank', async () => {
  const lb = (await s.call('GET', '/community/leaderboard', undefined, ann.token)).body;
  assert.ok(lb.month && lb.label);
  assert.ok(Array.isArray(lb.months) && lb.months[0].month === lb.month);
  assert.equal(lb.finalized, false);
  const row = lb.rows.find((r) => r.is_me);
  assert.ok(row, 'ann tagged places this month, so she is ranked');
  assert.equal(lb.my_rank, row.rank);
  assert.equal(JSON.stringify(lb).includes('user_id'), false, 'internal ids are not exposed');
  assert.equal((await s.call('GET', '/community/leaderboard?month=1999-01')).body.month, lb.month, 'an unknown month falls back to the current one');
  assert.equal((await s.call('GET', '/community/leaderboard')).body.my_rank, null, 'signed out has no rank');
});

test('a changed display name is what everyone sees: user search and the card showcase never show the real name', async () => {
  const a = await s.register('namea');
  const b = await s.register('nameb');
  await s.call('PUT', '/community/me', { display_name: 'ชื่อใหม่ของเอ' }, a.token);
  // search by the display name finds the person and returns it as the name
  const found = (await s.call('GET', `/users/search?q=${encodeURIComponent('ชื่อใหม่')}`, undefined, b.token)).body.users;
  assert.deepEqual(found.map((u) => [u.username, u.name]), [[a.username, 'ชื่อใหม่ของเอ']]);
  const plain = (await s.call('GET', `/users/search?q=${a.username}`, undefined, a.token)).body.users;
  assert.equal(plain.length, 0, 'you do not find yourself');
  // someone who never set a name shows as their username, not "nameb T"
  const other = (await s.call('GET', `/users/search?q=${b.username}`, undefined, cat.token)).body.users;
  assert.equal(other[0].name, b.username);
  assert.equal((await s.call('GET', `/profile/${a.username}`, undefined, b.token)).body.user.name, 'ชื่อใหม่ของเอ');
});
