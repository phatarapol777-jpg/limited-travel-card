process.env.KIOSK_SECRET = 'test-secret';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const { startServer, TINY_JPEG } = require('./helpers');

let s;
let adm;
let owner;
let other;
let locId;
let cardTpl; // a public card (a seeded location card)
let cardTpl2;

const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const week = () => Object.fromEntries(DAYS.map((d) => [d, [['09:00', '18:00']]]));
const jpegOfLength = (chars) => {
  // a valid JPEG signature followed by filler; base64 length is exactly `chars` (multiple of 4)
  const bytes = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(Math.floor((chars / 4) * 3) - 4, 7)]);
  return `data:image/jpeg;base64,${bytes.toString('base64')}`;
};

const form = (over = {}) => ({
  shop_name_th: 'คาเฟ่ทดสอบ', shop_name_en: 'Test Cafe', category: 'CAFE', description: 'กาแฟหอม บรรยากาศดี', address_detail: '12 ถ.ทดสอบ ต.ในเมือง อ.เมือง มหาสารคาม',
  latitude: 16.2, longitude: 103.28, nearby_location_id: locId, opening_hours: week(), phone: '081-234-5678',
  facebook: 'https://facebook.com/testcafe', instagram: 'https://instagram.com/testcafe', line: '@testcafe',
  cover_image: TINY_JPEG, gallery: [{ image: TINY_JPEG }, { image: TINY_JPEG }],
  items: [1, 2, 3].map((i) => ({ name: `เมนู ${i}`, price: 40 + i, image: TINY_JPEG, is_signature: i === 1 })),
  privileges: [{ template_id: cardTpl, description: 'แสดงการ์ดรับส่วนลดเครื่องดื่ม 10%', start_date: null, end_date: null }],
  ...over,
});
const create = (over, user = owner) => s.call('POST', '/merchants', form(over), user.token);
const approve = (id) => s.call('POST', `/admin/merchants/${id}/approve`, {}, adm.token);
const publicIds = async () => (await s.call('GET', '/merchants')).body.shops.map((x) => x.merchant_id);

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
  owner = await s.register('owner');
  other = await s.register('other');
  locId = (await s.call('GET', '/catalog/locations')).body.locations[0].location_id;
  const picker = (await s.call('GET', '/merchants/card-picker', undefined, owner.token)).body.cards;
  cardTpl = picker[0].template_id;
  cardTpl2 = picker[1].template_id;
});
test.after(() => s.stop());

test('the card picker needs a sign-in and lists only public cards (no pictures, no pending quest cards)', async () => {
  assert.equal((await s.call('GET', '/merchants/card-picker')).status, 401);
  const loc = (await s.call('GET', '/catalog/locations')).body.locations[0];
  const q = await s.call('POST', '/quests', {
    title: 'q', location_id: loc.location_id, description: 'd', cover_image: TINY_JPEG, permanent: true, card_name: 'การ์ดรออนุมัติ', card_image: TINY_JPEG, rarity: 'rare', mint_limit: 5,
  }, other.token);
  const pending = (await s.call('GET', '/merchants/card-picker', undefined, owner.token)).body;
  assert.equal(pending.cards.some((c) => c.name === 'การ์ดรออนุมัติ'), false, 'a pending quest card is not public');
  assert.equal(JSON.stringify(pending).includes('base64'), false);
  await s.call('POST', `/admin/quests/${q.body.quest_id}/approve`, {}, adm.token);
  assert.equal((await s.call('GET', '/merchants/card-picker', undefined, owner.token)).body.cards.some((c) => c.name === 'การ์ดรออนุมัติ'), true);
  const pack = await s.call('POST', '/admin/blind-packs', { name: 'ซองสุ่มสาธารณะ', rarity: 'rare', count: 1 }, adm.token);
  assert.equal((await s.call('GET', '/merchants/card-picker', undefined, owner.token)).body.cards.some((c) => c.template_id === pack.body.template_id), true, 'physical designs are listed');
});

test('form validation', async () => {
  const bad = [
    { shop_name_th: '' }, { shop_name_en: '' }, { category: 'BANK' }, { description: '' }, { address_detail: '' },
    { latitude: null }, { longitude: '' }, { latitude: 'x' }, { longitude: 10328192519501052 }, { latitude: 48.8, longitude: 2.3 },
    { nearby_location_id: 'nope' }, { phone: 'abc' }, { phone: '' },
    { facebook: 'javascript:alert(1)' }, { instagram: 'ftp://x.com/a' }, { line: 'not a handle' },
    { opening_hours: null }, { opening_hours: { ...week(), mon: [['9:00', '18:00']] } }, { opening_hours: { ...week(), mon: [['09:00', '09:00']] } },
    { opening_hours: { ...week(), tue: [['09:00', '10:00'], ['11:00', '12:00'], ['13:00', '14:00'], ['15:00', '16:00']] } },
    { cover_image: undefined }, { cover_image: 'data:image/png;base64,AAAA' },
    { gallery: Array(6).fill({ image: TINY_JPEG }) }, { gallery: [{ image: 'x' }] },
    { items: Array(9).fill({ name: 'a', price: 1, image: TINY_JPEG }) }, { items: [{ name: '', price: 1, image: TINY_JPEG }] },
    { items: [{ name: 'a', price: -5, image: TINY_JPEG }] }, { items: [{ name: 'a', price: 1, image: 'x' }] },
    { privileges: [{ template_id: 'nope', description: 'x' }] },
    { privileges: [{ template_id: cardTpl, description: '' }] },
    { privileges: [{ template_id: cardTpl, description: 'x' }, { template_id: cardTpl, description: 'y' }] },
    { privileges: [{ template_id: cardTpl, description: 'x', start_date: '2030-01-01' }] },
    { privileges: [{ template_id: cardTpl, description: 'x', start_date: '2030-02-01', end_date: '2030-01-01' }] },
    { privileges: [{ template_id: cardTpl, description: 'x', start_date: '2020-01-01', end_date: '2020-02-01' }] },
    { privileges: Array(6).fill(0).map((_, i) => ({ template_id: i % 2 ? cardTpl : cardTpl2, description: 'x' })) },
  ];
  for (const over of bad) {
    const r = await create(over);
    assert.equal(r.status, 400, JSON.stringify(over).slice(0, 90));
  }
  assert.equal((await s.call('POST', '/merchants', form())).status, 401);
});

let shopId;
test('a new shop waits for review: not public, visible to its owner and to admins only', async () => {
  const r = await create();
  assert.equal(r.status, 201);
  assert.equal(r.body.status, 'PENDING');
  shopId = r.body.merchant_id;
  assert.equal((await publicIds()).includes(shopId), false);
  assert.equal((await s.call('GET', `/merchants/${shopId}`)).status, 404);
  assert.equal((await s.call('GET', `/merchants/${shopId}`, undefined, other.token)).status, 404);
  assert.equal((await s.call('GET', `/merchants/${shopId}`, undefined, owner.token)).status, 200);
  assert.equal((await s.call('GET', `/merchants/${shopId}`, undefined, adm.token)).status, 200);
  assert.equal((await s.call('GET', `/media/merchant/${shopId}/cover`)).status, 404, 'pictures are private while pending');
  assert.equal((await s.call('GET', `/merchants/${shopId}/form`, undefined, other.token)).status, 404);
  const mine = (await s.call('GET', '/merchants/mine', undefined, owner.token)).body.shops.find((x) => x.merchant_id === shopId);
  assert.equal(mine.status, 'PENDING');
  const queue = (await s.call('GET', '/admin/merchants?status=PENDING', undefined, adm.token)).body.merchants;
  assert.ok(queue.some((x) => x.merchant_id === shopId && x.owner_username === owner.username));
  assert.equal((await s.call('GET', '/admin/merchants', undefined, owner.token)).status, 403);
});

test('reject with a reason, fix and resubmit, then approve: owner is told each time', async () => {
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/reject`, {}, adm.token)).status, 400, 'a reason is required');
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/reject`, { reason: 'พิกัดไม่ตรงกับที่อยู่' }, owner.token)).status, 403);
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/reject`, { reason: 'พิกัดไม่ตรงกับที่อยู่' }, adm.token)).status, 200);
  const mine = (await s.call('GET', '/merchants/mine', undefined, owner.token)).body.shops.find((x) => x.merchant_id === shopId);
  assert.equal(mine.status, 'REJECTED');
  assert.equal(mine.reject_reason, 'พิกัดไม่ตรงกับที่อยู่');
  let note = (await s.call('GET', '/notifications', undefined, owner.token)).body.notifications.find((n) => n.type === 'merchant_rejected');
  assert.match(note.text, /พิกัดไม่ตรงกับที่อยู่/);

  assert.equal((await s.call('PUT', `/merchants/${shopId}`, form({ shop_name_th: 'คาเฟ่ทดสอบ (แก้แล้ว)', latitude: 16.21 }), other.token)).status, 404);
  const fixed = await s.call('PUT', `/merchants/${shopId}`, form({ shop_name_th: 'คาเฟ่ทดสอบ (แก้แล้ว)', latitude: 16.21 }), owner.token);
  assert.equal(fixed.status, 200);
  assert.equal(fixed.body.status, 'PENDING');
  assert.equal((await s.call('GET', '/merchants/mine', undefined, owner.token)).body.shops.find((x) => x.merchant_id === shopId).reject_reason, null);

  assert.equal((await approve(shopId)).status, 200);
  assert.equal((await approve(shopId)).status, 409, 'nothing left to approve');
  note = (await s.call('GET', '/notifications', undefined, owner.token)).body.notifications.find((n) => n.type === 'merchant_approved');
  assert.match(note.text, /อนุมัติ/);
  assert.ok((await publicIds()).includes(shopId));
});

test('public views: map pin data, detail, pictures', async () => {
  const pin = (await s.call('GET', '/merchants')).body.shops.find((x) => x.merchant_id === shopId);
  assert.equal(pin.category, 'CAFE');
  assert.equal(pin.has_privilege, true, 'the gift badge is shown for shops with a card perk');
  assert.equal(typeof pin.open_now, 'boolean');
  assert.equal(pin.has_cover, true);
  assert.equal(JSON.stringify(pin).includes('base64'), false);
  assert.equal((await s.call('GET', '/merchants?category=RESTAURANT')).body.shops.some((x) => x.merchant_id === shopId), false, 'category filter');
  assert.equal((await s.call('GET', '/merchants?category=CAFE')).body.shops.some((x) => x.merchant_id === shopId), true);

  const d = (await s.call('GET', `/merchants/${shopId}`)).body;
  assert.equal(d.merchant.shop_name_th, 'คาเฟ่ทดสอบ (แก้แล้ว)');
  assert.equal(d.merchant.nearby_location.location_id, locId);
  assert.equal(d.gallery.length, 2);
  assert.equal(d.items.length, 3);
  assert.equal(d.items.find((i) => i.is_signature).name, 'เมนู 1');
  assert.equal(d.privileges.length, 1);
  assert.equal(d.privileges[0].valid_now, true);
  assert.equal(d.privileges[0].card.template_id, cardTpl);
  assert.equal(JSON.stringify(d).includes('base64'), false);
  assert.equal((await s.call('GET', `/media/merchant/${shopId}/cover`)).res.headers.get('content-type'), 'image/jpeg');
  assert.equal((await s.call('GET', `/media/merchant-gallery/${d.gallery[0].image_id}`)).status, 200);
  assert.equal((await s.call('GET', `/media/merchant-item/${d.items[0].item_id}`)).status, 200);
  assert.equal((await s.call('GET', '/media/merchant-item/nope')).status, 404);
});

test('shops that honour a card, and expired perks drop out', async () => {
  const list = (await s.call('GET', `/merchants/for-card/${cardTpl}`)).body.shops;
  const mine = list.find((x) => x.merchant_id === shopId);
  assert.ok(mine);
  assert.equal(mine.privilege.description, 'แสดงการ์ดรับส่วนลดเครื่องดื่ม 10%');
  assert.equal(typeof mine.latitude, 'number', 'coordinates are returned so the phone can sort by distance');
  assert.equal((await s.call('GET', `/merchants/for-card/${cardTpl2}`)).body.shops.some((x) => x.merchant_id === shopId), false);

  const db = s.sql();
  db.prepare('UPDATE merchant_privileges SET start_date = ?, end_date = ? WHERE merchant_id = ?').run('2020-01-01', '2020-12-31', shopId);
  db.close();
  assert.equal((await s.call('GET', `/merchants/for-card/${cardTpl}`)).body.shops.some((x) => x.merchant_id === shopId), false, 'expired');
  assert.equal((await s.call('GET', `/merchants/${shopId}`)).body.privileges.length, 0);
  assert.equal((await s.call('GET', '/merchants')).body.shops.find((x) => x.merchant_id === shopId).has_privilege, false, 'no badge without a valid perk');
  const db2 = s.sql();
  db2.prepare('UPDATE merchant_privileges SET start_date = NULL, end_date = NULL WHERE merchant_id = ?').run(shopId);
  db2.close();
});

test('editing a live shop makes a revision: the old version stays public until the change is approved', async () => {
  const before = (await s.call('GET', `/merchants/${shopId}`)).body;
  const oldItemId = before.items[0].item_id;
  const edit = await s.call('PUT', `/merchants/${shopId}`, form({
    shop_name_th: 'ชื่อใหม่ที่รอตรวจ', gallery: [{ image: TINY_JPEG }], items: [{ name: 'เมนูใหม่', price: 99, image: TINY_JPEG, is_signature: true }],
  }), owner.token);
  assert.equal(edit.status, 200);
  assert.equal(edit.body.revision_pending, true);
  assert.equal(edit.body.status, 'APPROVED');

  assert.equal((await s.call('GET', `/merchants/${shopId}`)).body.merchant.shop_name_th, 'คาเฟ่ทดสอบ (แก้แล้ว)', 'the public still sees the live version');
  assert.ok((await publicIds()).includes(shopId), 'it did not disappear from the map');
  const f = (await s.call('GET', `/merchants/${shopId}/form`, undefined, owner.token)).body;
  assert.equal(f.has_pending_revision, true);
  assert.equal(f.form.shop_name_th, 'ชื่อใหม่ที่รอตรวจ', 'the owner edits the waiting revision');
  const review = (await s.call('GET', `/admin/merchants/${shopId}`, undefined, adm.token)).body;
  assert.equal(review.reviewing, 'revision');
  assert.equal(review.form.shop_name_th, 'ชื่อใหม่ที่รอตรวจ');
  assert.ok((await s.call('GET', '/admin/merchants?status=PENDING', undefined, adm.token)).body.merchants.some((x) => x.merchant_id === shopId && x.has_revision));

  // a rejected change leaves the shop as it was
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/reject`, { reason: 'เมนูไม่ชัด' }, adm.token)).status, 200);
  const afterReject = (await s.call('GET', `/merchants/${shopId}/form`, undefined, owner.token)).body;
  assert.equal(afterReject.has_pending_revision, false);
  assert.equal(afterReject.revision_note, 'เมนูไม่ชัด');
  assert.equal(afterReject.status, 'APPROVED');
  assert.equal(afterReject.form.shop_name_th, 'คาเฟ่ทดสอบ (แก้แล้ว)');

  // send it again and approve: the live shop is replaced
  await s.call('PUT', `/merchants/${shopId}`, form({ shop_name_th: 'ชื่อใหม่ที่รอตรวจ', gallery: [{ image: TINY_JPEG }], items: [{ name: 'เมนูใหม่', price: 99, image: TINY_JPEG, is_signature: true }] }), owner.token);
  assert.equal((await approve(shopId)).status, 200);
  const after = (await s.call('GET', `/merchants/${shopId}`)).body;
  assert.equal(after.merchant.shop_name_th, 'ชื่อใหม่ที่รอตรวจ');
  assert.equal(after.gallery.length, 1);
  assert.equal(after.items.length, 1);
  assert.equal(after.items[0].name, 'เมนูใหม่');
  assert.equal((await s.call('GET', `/media/merchant-item/${after.items[0].item_id}`)).status, 200);
  assert.equal((await s.call('GET', `/media/merchant-item/${oldItemId}`)).status, 404, 'replaced items are gone');
  assert.equal((await s.call('GET', `/merchants/${shopId}/form`, undefined, owner.token)).body.has_pending_revision, false);
});

test('suspending hides a shop everywhere and blocks edits; unsuspending brings it back', async () => {
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/suspend`, { reason: 'ร้านปิดกิจการ' }, owner.token)).status, 403);
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/suspend`, { reason: 'ร้านปิดกิจการ' }, adm.token)).status, 200);
  assert.equal((await publicIds()).includes(shopId), false);
  assert.equal((await s.call('GET', `/merchants/${shopId}`)).status, 404);
  assert.equal((await s.call('GET', `/media/merchant/${shopId}/cover`)).status, 404);
  assert.equal((await s.call('GET', `/merchants/for-card/${cardTpl}`)).body.shops.some((x) => x.merchant_id === shopId), false);
  assert.equal((await s.call('PUT', `/merchants/${shopId}`, form(), owner.token)).status, 409);
  assert.equal((await s.call('GET', '/notifications', undefined, owner.token)).body.notifications.some((n) => n.type === 'merchant_suspended'), true);
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/suspend`, {}, adm.token)).status, 409, 'only live shops can be suspended');
  assert.equal((await s.call('POST', `/admin/merchants/${shopId}/unsuspend`, {}, adm.token)).status, 200);
  assert.ok((await publicIds()).includes(shopId));
});

test('a place with partner shops cannot be deleted', async () => {
  const r = await s.call('DELETE', `/admin/locations/${locId}`, undefined, adm.token);
  assert.equal(r.status, 400);
  assert.match(r.body.error, /ร้านค้า/);
});

test('withdrawing: pending or rejected shops can be deleted by the owner, live ones cannot', async () => {
  const draft = (await create({ shop_name_th: 'ร่างที่จะลบ' })).body.merchant_id;
  assert.equal((await s.call('DELETE', `/merchants/${draft}`, undefined, other.token)).status, 404);
  assert.equal((await s.call('DELETE', `/merchants/${draft}`, undefined, owner.token)).status, 200);
  assert.equal((await s.call('GET', `/merchants/${draft}`, undefined, owner.token)).status, 404);
  assert.equal((await s.call('DELETE', `/merchants/${shopId}`, undefined, owner.token)).status, 409);
  const db = s.sql();
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM merchant_items WHERE merchant_id = ?').get(draft).c, 0, 'its rows are removed too');
  db.close();
});

test('limits per account: 10 shops, 5 waiting for review', async () => {
  const u = await s.register('busy');
  for (let i = 0; i < 5; i++) assert.equal((await create({ shop_name_th: `ร้าน ${i}` }, u)).status, 201);
  const sixth = await create({ shop_name_th: 'ร้านที่ 6' }, u);
  assert.equal(sixth.status, 429);
  assert.match(sixth.body.error, /รออนุมัติ/);
  const list = (await s.call('GET', '/merchants/mine', undefined, u.token)).body.shops;
  for (const x of list) await approve(x.merchant_id);
  for (let i = 5; i < 10; i++) assert.equal((await create({ shop_name_th: `ร้าน ${i}` }, u)).status, 201);
  for (const x of (await s.call('GET', '/merchants/mine', undefined, u.token)).body.shops.filter((y) => y.status === 'PENDING')) await approve(x.merchant_id);
  assert.equal((await create({ shop_name_th: 'ร้านที่ 11' }, u)).status, 429);
});

test('image budget: oversize pictures are refused and a fully loaded shop stays under 1 MB', async () => {
  assert.equal((await create({ cover_image: jpegOfLength(170_000) })).status, 400, 'cover above its cap');
  assert.equal((await create({ gallery: [{ image: jpegOfLength(62_000) }] })).status, 400, 'gallery picture above its cap');
  assert.equal((await create({ items: [{ name: 'a', price: 1, image: jpegOfLength(62_000) }] })).status, 400, 'item picture above its cap');

  const u = await s.register('heavy');
  const dbPath = `${s.dataDir}/app.db`;
  const sizeNow = () => {
    const db = s.sql();
    const bytes = db.prepare('SELECT SUM(LENGTH(cover_image)) AS c FROM merchants').get().c + db.prepare('SELECT SUM(LENGTH(image)) AS c FROM merchant_gallery').get().c
      + db.prepare('SELECT SUM(LENGTH(image)) AS c FROM merchant_items').get().c;
    db.close();
    return bytes;
  };
  void fs; void dbPath;
  const before = sizeNow();
  const full = await create({
    cover_image: jpegOfLength(164_000),
    gallery: Array(5).fill({ image: jpegOfLength(59_000) }),
    items: Array(8).fill(0).map((_, i) => ({ name: `เมนู ${i}`, price: i, image: jpegOfLength(59_000), is_signature: false })),
  }, u);
  assert.equal(full.status, 201);
  const added = sizeNow() - before;
  assert.ok(added < 1_000_000, `a full shop added ${added} bytes of picture data`);
});

test('account deletion suspends the user shops', async () => {
  const u = await s.register('closing');
  const id = (await create({ shop_name_th: 'ร้านที่เจ้าของลบบัญชี' }, u)).body.merchant_id;
  await approve(id);
  assert.ok((await publicIds()).includes(id));
  assert.equal((await s.call('POST', '/auth/delete-account', { confirm_username: u.username }, u.token)).status, 200);
  assert.equal((await publicIds()).includes(id), false);
  const db = s.sql();
  assert.equal(db.prepare('SELECT approval_status FROM merchants WHERE merchant_id = ?').get(id).approval_status, 'SUSPENDED');
  db.close();
});

test('the old partner shops became approved merchants (and the old endpoints still answer)', async () => {
  const list = (await s.call('GET', '/merchants')).body.shops;
  const db = s.sql();
  const legacy = db.prepare('SELECT merchant_id, legacy_shop_id FROM merchants WHERE legacy_shop_id IS NOT NULL').all();
  db.close();
  assert.equal(legacy.length, 5);
  for (const l of legacy) assert.ok(list.some((x) => x.merchant_id === l.merchant_id), 'listed on the map');
  assert.equal((await s.call('GET', '/catalog/shops')).status, 200);
  assert.equal((await s.call('GET', `/catalog/locations/${locId}`)).status, 200);
});

test('admin stats carry a read-only summary of the newer modules (the PHP overview reads it)', async () => {
  const st = (await s.call('GET', '/admin/stats', undefined, adm.token)).body;
  assert.equal(typeof st.users, 'number', 'the old fields are still there');
  assert.ok(st.modules);
  assert.equal(st.modules.merchants.approved >= 5, true);
  for (const k of ['pending', 'approved', 'rejected', 'suspended', 'revisions_waiting', 'with_privileges']) assert.equal(typeof st.modules.merchants[k], 'number', k);
  for (const k of ['pending', 'approved', 'rejected', 'closed']) assert.equal(typeof st.modules.quests[k], 'number', k);
  assert.equal(typeof st.modules.blind_packs.designs, 'number');
  assert.equal(typeof st.modules.cards_voided, 'number');
  assert.equal((await s.call('GET', '/admin/stats', undefined, owner.token)).status, 403);
});
