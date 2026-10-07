const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tc-maint-'));
process.env.DATA_DIR = dir;
process.env.BACKUP = 'off';
process.env.KIOSK_SECRET = 'test-secret';
const db = require('../src/db');
require('../src/seed')();
const { purgeOldFacePhotos, pruneSessions } = require('../src/services/maintenance');
const settings = require('../src/services/settings');
const K = require('../src/services/kioskService');

const DAY = 86400000;

test('check-in face photos are dropped after 30 days, newer ones stay', () => {
  const kiosk = db.prepare('SELECT kiosk_id, location_id FROM checkin_kiosks LIMIT 1').get();
  const insert = db.prepare(`INSERT INTO checkin_sessions (session_id, kiosk_id, location_id, status, face_photo, created_at, expires_at)
    VALUES (?, ?, ?, 'completed', 'data:image/jpeg;base64,AAAA', ?, ?)`);
  const now = Date.now();
  insert.run('s-old', kiosk.kiosk_id, kiosk.location_id, new Date(now - 40 * DAY).toISOString(), new Date(now - 40 * DAY).toISOString());
  insert.run('s-edge', kiosk.kiosk_id, kiosk.location_id, new Date(now - 29 * DAY).toISOString(), new Date(now - 29 * DAY).toISOString());
  insert.run('s-new', kiosk.kiosk_id, kiosk.location_id, new Date(now - 1 * DAY).toISOString(), new Date(now - 1 * DAY).toISOString());
  assert.equal(purgeOldFacePhotos(now), 1);
  const photo = (id) => db.prepare('SELECT face_photo FROM checkin_sessions WHERE session_id = ?').get(id).face_photo;
  assert.equal(photo('s-old'), null);
  assert.notEqual(photo('s-edge'), null);
  assert.notEqual(photo('s-new'), null);
  assert.equal(purgeOldFacePhotos(now), 0, 'running again changes nothing');
  assert.equal(db.prepare("SELECT status FROM checkin_sessions WHERE session_id = 's-old'").get().status, 'completed', 'the audit row itself is kept');
});

test('expired sessions are pruned', () => {
  const user = db.prepare('SELECT user_id FROM users LIMIT 1').get().user_id;
  const now = Date.now();
  db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run('tok-old', user, new Date(now - 31 * DAY).toISOString());
  db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run('tok-new', user, new Date(now - 2 * DAY).toISOString());
  assert.ok(pruneSessions(now) >= 1);
  assert.equal(db.prepare("SELECT COUNT(*) AS c FROM sessions WHERE token = 'tok-old'").get().c, 0);
  assert.equal(db.prepare("SELECT COUNT(*) AS c FROM sessions WHERE token = 'tok-new'").get().c, 1);
});

test('settings drive the kiosk environment check and radius', () => {
  assert.equal(K.envCheckEnabled(), true);
  assert.equal(K.geoRadiusM(), 300);
  assert.equal(settings.set('env_check', false), null);
  assert.equal(settings.set('kiosk_geo_radius_m', 800), null);
  assert.equal(K.envCheckEnabled(), false);
  assert.equal(K.geoRadiusM(), 800);
  assert.match(settings.set('kiosk_geo_radius_m', 10), /50/);
  assert.equal(K.geoRadiusM(), 800, 'a rejected value changes nothing');
});
