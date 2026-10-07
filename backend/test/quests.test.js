// the same server secret the spawned server uses, so signatures made here verify there
process.env.KIOSK_SECRET = 'test-secret';
const test = require('node:test');
const assert = require('node:assert');
const { startServer, TINY_JPEG } = require('./helpers');
const Q = require('../src/services/questService');

let s;
let creator;
let claimer;
let third;
let adm;
let locationId;

test.before(async () => {
  s = await startServer();
  creator = await s.register('creator');
  claimer = await s.register('claimer');
  third = await s.register('third');
  adm = await s.admin();
  locationId = (await s.call('GET', '/catalog/locations')).body.locations[0].location_id;
});
test.after(() => s.stop());

const goodQuest = (over = {}) => ({
  title: 'ตามหาร้านกาแฟลับ', location_id: locationId, description: 'สั่งกาแฟแล้วสแกน QR ที่เคาน์เตอร์', cover_image: TINY_JPEG,
  permanent: true, card_name: 'การ์ดกาแฟลับ', card_image: TINY_JPEG, card_lore: 'ร้านเล็ก ๆ หลังตลาด', rarity: 'rare', mint_limit: 2, ...over,
});

test('bangkokToday follows Thai time, not UTC', () => {
  assert.equal(Q.bangkokToday(Date.parse('2026-10-07T16:59:00Z')), '2026-10-07');
  assert.equal(Q.bangkokToday(Date.parse('2026-10-07T17:01:00Z')), '2026-10-08');
});

test('questPhase: end date is inclusive', () => {
  const q = { permanent: 0, start_date: '2026-10-01', end_date: '2026-10-07' };
  assert.equal(Q.questPhase(q, '2026-09-30'), 'upcoming');
  assert.equal(Q.questPhase(q, '2026-10-07'), 'active');
  assert.equal(Q.questPhase(q, '2026-10-08'), 'ended');
  assert.equal(Q.questPhase({ permanent: 1 }, '2099-01-01'), 'active');
});

test('submitting needs login and valid data', async () => {
  assert.equal((await s.call('POST', '/quests', goodQuest())).status, 401);
  const bad = [
    goodQuest({ title: '' }), goodQuest({ description: '' }), goodQuest({ location_id: 'nope' }), goodQuest({ rarity: 'mythic' }),
    goodQuest({ mint_limit: 0 }), goodQuest({ mint_limit: 1.5 }), goodQuest({ mint_limit: 10_000_000 }),
    goodQuest({ cover_image: 'data:image/png;base64,AAAA' }), goodQuest({ card_image: 'nonsense' }),
    goodQuest({ cover_image: `data:image/jpeg;base64,${Buffer.from('not a jpeg at all').toString('base64')}` }),
    goodQuest({ permanent: false }), goodQuest({ permanent: false, start_date: '2026-13-40', end_date: '2026-12-01' }),
    goodQuest({ permanent: false, start_date: '2099-02-01', end_date: '2099-01-01' }),
    goodQuest({ permanent: false, start_date: '2020-01-01', end_date: '2020-01-02' }),
    goodQuest({ cover_image: `data:image/jpeg;base64,${'A'.repeat(Q.MAX_COVER_CHARS + 10)}` }),
  ];
  for (const b of bad) assert.equal((await s.call('POST', '/quests', b, creator.token)).status, 400, JSON.stringify(b).slice(0, 80));
});

let questId;
test('a valid request is stored as pending and its images stay private', async () => {
  const r = await s.call('POST', '/quests', goodQuest(), creator.token);
  assert.equal(r.status, 201);
  assert.equal(r.body.status, 'pending');
  questId = r.body.quest_id;

  const mine = await s.call('GET', '/quests/mine', undefined, creator.token);
  assert.equal(mine.body.quests[0].status, 'pending');
  assert.equal(JSON.stringify(mine.body).includes('base64'), false, 'no image data in lists');
  assert.equal((await s.call('GET', '/quests', undefined)).body.quests.length, 0, 'pending quests are not public');

  assert.equal((await s.call('GET', `/media/quest/${questId}/cover`)).status, 404);
  const db = s.sql();
  const tpl = db.prepare('SELECT template_id FROM card_templates WHERE quest_id = ?').get(questId).template_id;
  db.close();
  assert.equal((await s.call('GET', `/media/card/${tpl}`)).status, 404);
  assert.equal((await s.call('GET', `/quests/${questId}/images`, undefined, claimer.token)).status, 404);
  assert.equal((await s.call('GET', `/quests/${questId}/images`, undefined, creator.token)).status, 200);
  assert.equal((await s.call('GET', `/admin/quests/${questId}/images`, undefined, adm.token)).status, 200);
});

test('a pending quest cannot be claimed and has no QR yet', async () => {
  const qr = await s.call('GET', `/quests/${questId}/qr`, undefined, creator.token);
  assert.equal(qr.status, 409);
  const forged = await s.call('POST', '/quests/claim', { payload: Q.questPayload(questId) }, claimer.token);
  assert.equal(forged.status, 409);
  assert.match(forged.body.error, /รอการอนุมัติ/);
});

test('admin endpoints are admin-only; reject needs a reason', async () => {
  assert.equal((await s.call('GET', '/admin/quests', undefined, creator.token)).status, 403);
  assert.equal((await s.call('POST', `/admin/quests/${questId}/approve`, {}, creator.token)).status, 403);
  assert.equal((await s.call('POST', `/admin/quests/${questId}/reject`, {}, adm.token)).status, 400);
});

test('approval notifies the creator and unlocks the QR and public images', async () => {
  assert.equal((await s.call('POST', `/admin/quests/${questId}/approve`, {}, adm.token)).status, 200);
  assert.equal((await s.call('POST', `/admin/quests/${questId}/approve`, {}, adm.token)).status, 409, 'cannot review twice');
  const n = await s.call('GET', '/notifications', undefined, creator.token);
  assert.equal(n.body.unread, 1);
  assert.equal(n.body.notifications[0].type, 'quest_approved');
  assert.equal((await s.call('POST', '/notifications/read', {}, creator.token)).status, 200);
  assert.equal((await s.call('GET', '/notifications', undefined, creator.token)).body.unread, 0);

  assert.equal((await s.call('GET', `/quests/${questId}/qr`, undefined, claimer.token)).status, 404, 'only the creator gets the QR');
  const qr = await s.call('GET', `/quests/${questId}/qr`, undefined, creator.token);
  assert.equal(qr.status, 200);
  assert.match(qr.body.payload, /^TRVQUEST\|qst-[a-f0-9]+\|[a-f0-9]{24}$/);
  s.payload = qr.body.payload;

  const cover = await s.call('GET', `/media/quest/${questId}/cover`);
  assert.equal(cover.status, 200);
  assert.equal(cover.res.headers.get('content-type'), 'image/jpeg');
  assert.equal((await s.call('GET', '/quests')).body.quests.length, 1);
});

test('forged or malformed QR payloads are rejected', async () => {
  const [prefix, id, sig] = s.payload.split('|');
  for (const payload of [`${prefix}|${id}|${'0'.repeat(24)}`, `${prefix}|${id}|${sig.slice(0, 20)}`, `${prefix}|${id}`, `X|${id}|${sig}`, '', null, 42, `${prefix}|qst-other|${sig}`]) {
    assert.equal((await s.call('POST', '/quests/claim', { payload }, claimer.token)).status, 400, String(payload));
  }
  assert.equal((await s.call('POST', '/quests/claim', { payload: s.payload })).status, 401);
});

test('claims: serials count up, a user can claim once, the limit holds', async () => {
  const first = await s.call('POST', '/quests/claim', { payload: s.payload }, claimer.token);
  assert.equal(first.status, 201);
  assert.equal(first.body.card.serial_label, '#001/2');
  assert.equal(first.body.card.activation_status, 'CLAIMED');
  assert.equal(first.body.card.card_type, 'QUEST_LOCATION');
  assert.equal(first.body.card.rarity, 'rare');
  assert.equal(JSON.stringify(first.body).includes('base64'), false);

  const again = await s.call('POST', '/quests/claim', { payload: s.payload }, claimer.token);
  assert.equal(again.status, 409);
  assert.match(again.body.error, /รับการ์ดจากภารกิจนี้ไปแล้ว/);

  const second = await s.call('POST', '/quests/claim', { payload: s.payload }, creator.token);
  assert.equal(second.status, 201);
  assert.equal(second.body.card.serial_label, '#002/2');

  const late = await s.call('POST', '/quests/claim', { payload: s.payload }, third.token);
  assert.equal(late.status, 409);
  assert.match(late.body.error, /ครบจำนวน/);

  const listed = (await s.call('GET', '/quests')).body.quests[0];
  assert.equal(listed.card.remaining, 0);
  const mineCards = (await s.call('GET', '/cards', undefined, claimer.token)).body.cards;
  assert.equal(mineCards.filter((c) => c.quest_id === questId).length, 1);
  const db = s.sql();
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM card_ownership_log WHERE reason = ?').get('quest').c, 2);
  db.close();
});

test('simultaneous claims never exceed the limit', async () => {
  const q2 = (await s.call('POST', '/quests', goodQuest({ mint_limit: 3 }), creator.token)).body.quest_id;
  await s.call('POST', `/admin/quests/${q2}/approve`, {}, adm.token);
  const payload = (await s.call('GET', `/quests/${q2}/qr`, undefined, creator.token)).body.payload;
  const users = await Promise.all(Array.from({ length: 8 }, (_, i) => s.register(`racer${i}`)));
  const results = await Promise.all(users.map((u) => s.call('POST', '/quests/claim', { payload }, u.token)));
  const ok = results.filter((r) => r.status === 201);
  assert.equal(ok.length, 3);
  assert.deepEqual(ok.map((r) => r.body.card.serial_number).sort(), [1, 2, 3]);
});

test('date window: upcoming and ended refuse, the end date itself still works (Thai time)', async () => {
  const mkQuest = async (patch) => {
    const id = (await s.call('POST', '/quests', goodQuest({ mint_limit: 50 }), creator.token)).body.quest_id;
    await s.call('POST', `/admin/quests/${id}/approve`, {}, adm.token);
    const db = s.sql();
    db.prepare('UPDATE quests SET permanent = 0, start_date = ?, end_date = ? WHERE quest_id = ?').run(patch.start, patch.end, id);
    db.close();
    return (await s.call('GET', `/quests/${id}/qr`, undefined, creator.token)).body.payload;
  };
  const today = Q.bangkokToday();
  const shift = (d, days) => new Date(Date.parse(`${d}T00:00:00Z`) + days * 86400000).toISOString().slice(0, 10);
  const user = await s.register('dated');
  const upcoming = await mkQuest({ start: shift(today, 1), end: shift(today, 5) });
  assert.match((await s.call('POST', '/quests/claim', { payload: upcoming }, user.token)).body.error, /จะเริ่มวันที่/);
  const ended = await mkQuest({ start: shift(today, -5), end: shift(today, -1) });
  assert.match((await s.call('POST', '/quests/claim', { payload: ended }, user.token)).body.error, /หมดเวลา/);
  const lastDay = await mkQuest({ start: shift(today, -5), end: today });
  assert.equal((await s.call('POST', '/quests/claim', { payload: lastDay }, user.token)).status, 201);
});

test('rejecting records the reason, notifies the creator, and the QR stays unusable', async () => {
  const id = (await s.call('POST', '/quests', goodQuest(), creator.token)).body.quest_id;
  assert.equal((await s.call('POST', `/admin/quests/${id}/reject`, { reason: 'รูปไม่ชัด' }, adm.token)).status, 200);
  const mine = (await s.call('GET', '/quests/mine', undefined, creator.token)).body.quests.find((q) => q.quest_id === id);
  assert.equal(mine.status, 'rejected');
  assert.equal(mine.reject_reason, 'รูปไม่ชัด');
  const n = (await s.call('GET', '/notifications', undefined, creator.token)).body.notifications[0];
  assert.equal(n.type, 'quest_rejected');
  assert.match(n.text, /รูปไม่ชัด/);
  assert.equal((await s.call('POST', '/quests/claim', { payload: Q.questPayload(id) }, claimer.token)).status, 409);
  assert.equal((await s.call('GET', `/media/quest/${id}/cover`)).status, 404);
});

test('a location with quests cannot be deleted', async () => {
  const r = await s.call('DELETE', `/admin/locations/${locationId}`, undefined, adm.token);
  assert.equal(r.status, 400);
});
