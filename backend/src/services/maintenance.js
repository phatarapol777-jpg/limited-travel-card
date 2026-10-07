const db = require('../db');

const PHOTO_RETENTION_DAYS = 30;
const SESSION_MAX_AGE_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Face photos taken at the kiosk are personal data: keep them for a month for audits, then drop the picture. */
function purgeOldFacePhotos(now = Date.now()) {
  const cutoff = new Date(now - PHOTO_RETENTION_DAYS * DAY_MS).toISOString();
  return db.prepare('UPDATE checkin_sessions SET face_photo = NULL WHERE face_photo IS NOT NULL AND created_at < ?').run(cutoff).changes;
}

function pruneSessions(now = Date.now()) {
  const cutoff = new Date(now - SESSION_MAX_AGE_DAYS * DAY_MS).toISOString();
  return db.prepare('DELETE FROM sessions WHERE created_at < ?').run(cutoff).changes;
}

function runAll() {
  const photos = purgeOldFacePhotos();
  const sessions = pruneSessions();
  const months = require('./leaderboard').finalizePastMonths();
  if (months.length) console.log(`[maintenance] closed community months: ${months.join(', ')}`);
  if (photos || sessions) console.log(`[maintenance] removed ${photos} old face photos and ${sessions} expired sessions`);
}

/** Runs now and every 6 hours. */
function start() {
  try { runAll(); } catch (e) { console.error('[maintenance]', e.message); }
  setInterval(() => { try { runAll(); } catch (e) { console.error('[maintenance]', e.message); } }, 6 * 60 * 60 * 1000).unref();
}

module.exports = { purgeOldFacePhotos, pruneSessions, start, PHOTO_RETENTION_DAYS, SESSION_MAX_AGE_DAYS };
