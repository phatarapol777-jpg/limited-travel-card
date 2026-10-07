const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tc-board-'));
process.env.DATA_DIR = dir;
process.env.BACKUP = 'off';
process.env.KIOSK_SECRET = 'test-secret';
const db = require('../src/db');
require('../src/seed')();
const board = require('../src/services/leaderboard');
const settings = require('../src/services/settings');

const locs = db.prepare('SELECT location_id FROM locations ORDER BY location_id').all().map((l) => l.location_id);
let seq = 0;
function user(name) {
  const id = `usr-${name}`;
  db.prepare('INSERT INTO users (user_id, username, password_hash, password_salt, first_name, last_name, email, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .run(id, name, 'x', 'y', name, 'T', `${name}@x.com`, new Date().toISOString());
  return id;
}
// timestamps below are written in Thai time (UTC+7) and stored as UTC, like the server does
const thai = (iso) => new Date(Date.parse(`${iso}+07:00`)).toISOString();
function post(userId, locIdx, when, status = 'visible') {
  db.prepare("INSERT INTO community_posts (post_id, user_id, content, status, timestamp, location_id) VALUES (?, ?, 'x', ?, ?, ?)")
    .run(`p${++seq}`, userId, status, thai(when), locIdx === null ? null : locs[locIdx]);
}
const now = (iso) => Date.parse(`${iso}+07:00`);

const ann = user('ann');
const ben = user('ben');
const cat = user('cat');
const dan = user('dan');

// September 2026
post(ann, 0, '2026-09-03T10:00:00');
post(ann, 1, '2026-09-04T10:00:00');
post(ann, 1, '2026-09-05T10:00:00'); // same place again: counts once
post(ann, 2, '2026-09-30T23:30:00'); // 23:30 Thai time on the last day is still September (it is 16:30 UTC), so ann reaches 3 last
post(ben, 0, '2026-09-06T10:00:00');
post(ben, 1, '2026-09-07T10:00:00');
post(ben, 2, '2026-09-08T10:00:00');
post(cat, 0, '2026-09-06T09:00:00');
post(cat, 1, '2026-09-06T09:30:00');
post(cat, 2, '2026-09-09T09:00:00'); // ties with ben on 3, but one day later
post(dan, 0, '2026-09-10T10:00:00', 'hidden'); // hidden posts do not count
post(dan, null, '2026-09-10T11:00:00'); // no place tagged: does not count
post(dan, 0, '2026-10-01T00:30:00'); // 00:30 Thai time on 1 October (17:30 UTC on 30 September) belongs to October

test('ranking counts different places only, in Thai-time months, ignoring hidden and untagged posts', () => {
  const sep = board.computeMonth('2026-09');
  assert.deepEqual(sep.map((r) => [r.user_id, r.unique_count, r.rank]), [[ben, 3, 1], [cat, 3, 2], [ann, 3, 3]]);
  const oct = board.computeMonth('2026-10');
  assert.deepEqual(oct.map((r) => [r.user_id, r.unique_count]), [[dan, 1]]);
});

test('a finished month is closed once: stored ranking, badges for the top N, one notice each, nothing twice', () => {
  const closed = board.finalizePastMonths(now('2026-10-02T09:00:00'));
  assert.deepEqual(closed, ['2026-09']);
  assert.deepEqual(board.finalizePastMonths(now('2026-10-02T10:00:00')), [], 'asking again changes nothing');

  const badges = db.prepare('SELECT user_id, rank_position, icon, title FROM user_badges ORDER BY rank_position').all();
  assert.deepEqual(badges.map((b) => [b.user_id, b.rank_position, b.icon]), [[ben, 1, 'gold'], [cat, 2, 'silver'], [ann, 3, 'bronze']]);
  assert.match(badges[0].title, /กันยายน 2569/, 'titles use the Thai month and Buddhist year');
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM notifications WHERE type = ?').get('community_badge').c, 3);
  assert.equal(db.prepare('SELECT selected_badge_id FROM users WHERE user_id = ?').get(ann).selected_badge_id, db.prepare('SELECT badge_id FROM user_badges WHERE user_id = ?').get(ann).badge_id, 'the new badge is worn by default');
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM checkin_monthly_stats WHERE year_month = ?').get('2026-09').c, 3);

  // late changes cannot rewrite a closed month
  post(dan, 0, '2026-09-11T10:00:00');
  post(dan, 1, '2026-09-11T11:00:00');
  post(dan, 2, '2026-09-11T12:00:00');
  board.finalizePastMonths(now('2026-10-05T09:00:00'));
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM user_badges').get().c, 3);
  const lb = board.leaderboard('2026-09', now('2026-10-05T09:00:00'));
  assert.equal(lb.finalized, true);
  assert.deepEqual(lb.rows.map((r) => r.rank), [1, 2, 3]);
});

test('the running month is live and several skipped months are all closed on the next request', () => {
  const live = board.leaderboard('2026-10', now('2026-10-05T09:00:00'));
  assert.equal(live.finalized, false);
  assert.equal(live.rows[0].author.display_name, 'dan');

  post(ann, 0, '2026-11-02T10:00:00');
  const closed = board.finalizePastMonths(now('2027-02-03T09:00:00')); // the server slept through Dec and Jan
  assert.deepEqual(closed, ['2026-10', '2026-11', '2026-12', '2027-01']);
  assert.deepEqual(board.availableMonths(now('2027-02-03T09:00:00')), ['2027-02', '2027-01', '2026-12', '2026-11', '2026-10', '2026-09']);
  assert.equal(db.prepare("SELECT COUNT(*) AS c FROM user_badges WHERE awarded_month = '2026-12'").get().c, 0, 'an empty month awards nothing');
});

test('ties go to whoever reached the count first, then to the smaller id', () => {
  const x = user('xx');
  const y = user('yy');
  post(y, 0, '2027-03-01T09:00:00');
  post(x, 0, '2027-03-01T09:00:00'); // same instant
  const r = board.computeMonth('2027-03');
  assert.deepEqual(r.map((q) => q.user_id), [y, x].sort(), 'identical time falls back to the user id');
  post(x, 1, '2027-03-02T09:00:00');
  post(y, 1, '2027-03-02T08:00:00');
  assert.equal(board.computeMonth('2027-03')[0].user_id, y, 'y reached two places earlier');
});

test('verification switch: only tags the person could really have visited', () => {
  settings.set('community_tag_verify', true);
  try {
    const v = user('vv');
    post(v, 0, '2027-04-01T09:00:00');
    post(v, 1, '2027-04-02T09:00:00');
    assert.deepEqual(board.computeMonth('2027-04'), [], 'no check-in, no card: nothing counts');
    db.prepare("INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status) VALUES ('h1', ?, ?, ?, 'success')").run(v, locs[0], new Date().toISOString());
    assert.deepEqual(board.computeMonth('2027-04').map((r) => r.unique_count), [1], 'a real check-in makes that place count');
  } finally {
    settings.set('community_tag_verify', false);
  }
});

test('the number of badge winners is a setting', () => {
  settings.set('community_badge_top_n', 1);
  try {
    const a = user('na');
    const b = user('nb');
    post(a, 0, '2027-05-02T09:00:00');
    post(a, 1, '2027-05-03T09:00:00');
    post(b, 0, '2027-05-02T10:00:00');
    board.finalizePastMonths(now('2027-06-02T09:00:00'));
    assert.deepEqual(db.prepare("SELECT user_id FROM user_badges WHERE awarded_month = '2027-05'").all().map((r) => r.user_id), [a]);
    assert.equal(db.prepare("SELECT COUNT(*) AS c FROM checkin_monthly_stats WHERE year_month = '2027-05'").get().c, 2, 'everyone is still ranked');
  } finally {
    settings.set('community_badge_top_n', 3);
  }
});
