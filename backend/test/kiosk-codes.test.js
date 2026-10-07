const test = require('node:test');
const assert = require('node:assert');
const { startServer } = require('./helpers');

let s;
let adm;

const location = (name) => ({ name, province: 'มหาสารคาม', latitude: 16.2, longitude: 103.3, mission_title: 'ภารกิจ', card_name: 'การ์ด', card_rarity: 'normal' });

test.before(async () => {
  s = await startServer();
  adm = await s.admin();
});
test.after(() => s.stop());

test('every new place gets its own kiosk code and key', async () => {
  for (const name of ['สวนหนึ่ง', 'สวนสอง', 'สวนสาม']) assert.equal((await s.call('POST', '/admin/locations', location(name), adm.token)).status, 201);
  const kiosks = (await s.call('GET', '/admin/kiosks', undefined, adm.token)).body.kiosks;
  assert.equal(kiosks.length, 9);
  const codes = kiosks.map((k) => k.kiosk_code);
  const keys = kiosks.map((k) => k.kiosk_key);
  assert.ok(codes.every((c) => /^KSK-\d{3}$/.test(c)), codes.join());
  assert.equal(new Set(codes).size, 9, 'codes are unique');
  assert.equal(new Set(keys).size, 9, 'keys are unique');
  assert.deepEqual(codes.slice(-3), ['KSK-007', 'KSK-008', 'KSK-009']);
});

test('a new kiosk can sign in with its own key, and not with another kiosk key', async () => {
  const kiosks = (await s.call('GET', '/admin/kiosks', undefined, adm.token)).body.kiosks;
  const fresh = kiosks.find((k) => k.kiosk_code === 'KSK-009');
  const other = kiosks.find((k) => k.kiosk_code === 'KSK-001');
  const beat = (code, key) => fetch(`${s.base}/kiosk/${code}/heartbeat`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-kiosk-key': key }, body: '{}' });
  assert.equal((await beat(fresh.kiosk_code, fresh.kiosk_key)).status, 200);
  assert.equal((await beat(fresh.kiosk_code, other.kiosk_key)).status, 401);
});

test('kiosks that were saved without a code are repaired, each getting a different one', async () => {
  const db = s.sql();
  const loc = db.prepare('SELECT location_id FROM locations LIMIT 1').get().location_id;
  const now = Date.now();
  for (let i = 0; i < 3; i++) {
    db.prepare("INSERT INTO checkin_kiosks (kiosk_id, location_id, mac_address, mock_ble_signal, status) VALUES (?, ?, ?, 'BLE', 'online')")
      .run(`kiosk-legacy-${now}-${i}`, loc, `AA:BB:CC:99:${i}:${now % 100}`);
  }
  db.close();
  const kiosks = (await s.call('GET', '/admin/kiosks', undefined, adm.token)).body.kiosks;
  assert.equal(kiosks.length, 12);
  assert.ok(kiosks.every((k) => k.kiosk_code), 'no kiosk is left without a code');
  assert.equal(new Set(kiosks.map((k) => k.kiosk_key)).size, 12);
  assert.equal(new Set(kiosks.map((k) => k.kiosk_code)).size, 12);
});

test('a key can never be made for a missing code', () => {
  process.env.KIOSK_SECRET = 'test-secret';
  const { kioskKey } = require('../src/services/kioskService');
  assert.throws(() => kioskKey(null));
  assert.throws(() => kioskKey(''));
});
