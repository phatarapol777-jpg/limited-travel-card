const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tc-merch-'));
process.env.DATA_DIR = dir;
process.env.BACKUP = 'off';
process.env.KIOSK_SECRET = 'test-secret';
const db = require('../src/db');
require('../src/seed')();
const M = require('../src/services/merchantService');

// Thai time is UTC+7. These timestamps are written in Thai time and converted.
const thai = (iso) => Date.parse(`${iso}+07:00`);
const week = (over = {}) => ({ mon: [['09:00', '18:00']], tue: [['09:00', '18:00']], wed: [['09:00', '18:00']], thu: [['09:00', '18:00']], fri: [['09:00', '18:00']], sat: [], sun: [], ...over });

test('open now: inside, before, at closing (exclusive), and closed days', () => {
  const h = week();
  assert.equal(M.isOpenNow(h, thai('2026-10-05T10:00:00')), true); // Monday
  assert.equal(M.isOpenNow(h, thai('2026-10-05T08:59:00')), false);
  assert.equal(M.isOpenNow(h, thai('2026-10-05T09:00:00')), true);
  assert.equal(M.isOpenNow(h, thai('2026-10-05T18:00:00')), false, 'closing time itself is closed');
  assert.equal(M.isOpenNow(h, thai('2026-10-05T17:59:00')), true);
  assert.equal(M.isOpenNow(h, thai('2026-10-10T12:00:00')), false, 'Saturday has no ranges');
  assert.equal(M.isOpenNow(null), false);
});

test('open now uses Thai time, not UTC: UTC clock is seven hours behind', () => {
  const h = week();
  assert.equal(M.isOpenNow(h, Date.parse('2026-10-05T02:30:00Z')), true); // 09:30 Monday in Thailand
  assert.equal(M.isOpenNow(h, Date.parse('2026-10-04T23:30:00Z')), false); // 06:30 Monday in Thailand
  assert.equal(M.isOpenNow(h, Date.parse('2026-10-05T10:30:00Z')), true); // 17:30 Monday in Thailand, still open
  assert.equal(M.isOpenNow(h, Date.parse('2026-10-05T11:30:00Z')), false); // 18:30 Monday in Thailand, closed
});

test('ranges that run past midnight: a bar open 18:00 to 02:00', () => {
  const h = week({ fri: [['18:00', '02:00']] });
  assert.equal(M.isOpenNow(h, thai('2026-10-09T17:59:00')), false); // Friday before opening
  assert.equal(M.isOpenNow(h, thai('2026-10-09T23:00:00')), true); // Friday night
  assert.equal(M.isOpenNow(h, thai('2026-10-10T01:00:00')), true); // Saturday 01:00 belongs to Friday's range
  assert.equal(M.isOpenNow(h, thai('2026-10-10T02:00:00')), false);
  assert.equal(M.isOpenNow(h, thai('2026-10-10T12:00:00')), false);
});

test('today text in Thai time', () => {
  const h = week({ mon: [['09:00', '12:00'], ['13:00', '18:00']] });
  assert.equal(M.todayHoursText(h, thai('2026-10-05T10:00:00')), '09:00 - 12:00, 13:00 - 18:00');
  assert.equal(M.todayHoursText(h, thai('2026-10-10T10:00:00')), 'ปิดทำการวันนี้');
});

test('hours validation', () => {
  assert.ok(M.validateHours(week()).hours);
  assert.ok(M.validateHours({}).hours, 'missing days mean closed');
  for (const bad of [null, [], 'x', week({ mon: 'x' }), week({ mon: [['25:00', '26:00']] }), week({ mon: [['09:00']] }), week({ mon: [['09:00', '09:00']] })]) {
    assert.ok(M.validateHours(bad).error, JSON.stringify(bad));
  }
});

test('the seeded partner shops become merchants once, however many times it runs', () => {
  const before = db.prepare('SELECT COUNT(*) AS c FROM merchants').get().c;
  const first = M.migrateLegacyShops();
  const second = M.migrateLegacyShops();
  const after = db.prepare('SELECT COUNT(*) AS c FROM merchants').get().c;
  assert.equal(before, 0);
  assert.equal(first, 5);
  assert.equal(second, 0);
  assert.equal(after, 5);
  const row = db.prepare("SELECT * FROM merchants WHERE category = 'CAFE'").get();
  assert.equal(row.approval_status, 'APPROVED');
  assert.ok(row.legacy_shop_id);
  assert.ok(row.latitude > 5 && row.latitude < 21);
});
