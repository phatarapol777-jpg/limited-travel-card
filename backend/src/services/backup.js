// Keeps the SQLite database across restarts on hosts with a throw-away disk (Render's free tier).
// The database is serialised, gzipped and AES-256-GCM encrypted with a key derived from the server secret, then
// stored on a separate host (admin-php/backup.php). On boot with no database file, the latest snapshot is restored.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { derive, dataDir } = require('../secret');

const URL = process.env.BACKUP_URL || 'http://202.28.34.205:8080/273/backup.php';
const ENABLED = String(process.env.BACKUP || 'on').toLowerCase() !== 'off' && !!URL;
const INTERVAL_MS = 15000; // how often we check whether something changed
const MIN_GAP_MS = 60000; // but never upload two snapshots closer together than this (each one is the whole database)
const MAGIC = Buffer.from('TCB1');
const token = derive('backup-token').toString('hex');
const key = derive('backup-key');

let dirty = false;
let uploading = false;
let uploadedOnce = false;
let lastUploadAt = 0;
const state = { lastSuccessAt: null, lastErrorAt: null, lastError: null, lastSizeKb: null, uploads: 0 };
let blocked = false; // true when a restore failed: never overwrite the stored snapshot with a fresh database
let db = null;

function encrypt(plain) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), body]);
}

function decrypt(blob) {
  if (blob.length < MAGIC.length + 28 || !blob.subarray(0, 4).equals(MAGIC)) throw new Error('not a backup snapshot');
  const iv = blob.subarray(4, 16);
  const tag = blob.subarray(16, 32);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(blob.subarray(32)), decipher.final()]);
}

/** Before the database is opened: if there is no database file, try to restore the last snapshot. */
async function restoreIfMissing() {
  if (!ENABLED) return;
  const file = path.join(dataDir, 'app.db');
  if (fs.existsSync(file)) return;
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(URL, { headers: { 'x-backup-token': token }, signal: AbortSignal.timeout(20000) });
      if (res.status === 404) return console.log('[backup] no snapshot stored yet, starting fresh');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = zlib.gunzipSync(decrypt(Buffer.from(await res.arrayBuffer())));
      fs.mkdirSync(dataDir, { recursive: true });
      fs.writeFileSync(file, data);
      return console.log(`[backup] restored database snapshot (${data.length} bytes)`);
    } catch (err) {
      lastError = err;
      console.error(`[backup] restore attempt ${attempt} failed:`, err.message);
      if (attempt < 3) await new Promise((r) => setTimeout(r, 4000));
    }
  }
  blocked = true;
  console.error('[backup] could not restore; starting fresh and NOT uploading, so the stored snapshot stays safe:', lastError && lastError.message);
}

async function upload(force = false) {
  if (!ENABLED || blocked || !db || uploading || !dirty) return;
  if (!force && Date.now() - lastUploadAt < MIN_GAP_MS) return; // still dirty: the next tick after the gap uploads it
  uploading = true;
  dirty = false;
  lastUploadAt = Date.now();
  try {
    const blob = encrypt(zlib.gzipSync(db.serialize()));
    const res = await fetch(URL, {
      method: 'POST',
      headers: { 'x-backup-token': token, 'content-type': 'application/octet-stream' },
      body: blob,
      signal: AbortSignal.timeout(30000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const kb = Math.round(blob.length / 1024);
    if (blob.length > 60 * 1024 * 1024) console.error(`[backup] WARNING: snapshot is ${kb} KB, close to the host's 100 MB limit`);
    else if (kb > 4096 || !uploadedOnce) console.log(`[backup] uploaded ${kb} KB`);
    uploadedOnce = true;
    state.lastSuccessAt = new Date().toISOString();
    state.lastSizeKb = kb;
    state.uploads += 1;
  } catch (err) {
    dirty = true; // try again on the next tick
    state.lastError = err.message;
    state.lastErrorAt = new Date().toISOString();
    console.error('[backup] upload failed:', err.message);
  } finally {
    uploading = false;
  }
}

function markDirty() {
  dirty = true;
}

/** Starts periodic uploads once the database is open. */
function start(database) {
  if (!ENABLED) return console.log('[backup] disabled');
  db = database;
  dirty = true; // the first tick stores a snapshot of whatever was restored or seeded
  setInterval(upload, INTERVAL_MS).unref();
  console.log(`[backup] snapshots go to ${URL}`);
}

async function flush() {
  dirty = dirty || ENABLED;
  uploading = false;
  await upload(true);
}

/** For the admin dashboard: is the safety net working? */
function status() {
  return { enabled: ENABLED, blocked, pending_changes: dirty, ...state };
}

module.exports = { restoreIfMissing, start, markDirty, flush, status, encrypt, decrypt };
