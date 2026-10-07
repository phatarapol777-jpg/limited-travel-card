const crypto = require('crypto');
const { derive } = require('../secret');

const QR_PREFIX = 'TRVQUEST';
const MAX_COVER_CHARS = 450_000; // ~330 KB of JPEG once decoded
const MAX_CARD_IMAGE_CHARS = 800_000; // ~600 KB
const SIG_LENGTH = 24;

/** The quest QR carries a signature made with a server-derived key, so it still verifies after a database restore. */
function questSig(questId) {
  return crypto.createHmac('sha256', derive('quest-qr')).update(`quest|${questId}`).digest('hex').slice(0, SIG_LENGTH);
}

function questPayload(questId) {
  return `${QR_PREFIX}|${questId}|${questSig(questId)}`;
}

/** Returns the quest id when the payload is a correctly signed quest QR, otherwise null. */
function parseQuestPayload(payload) {
  if (typeof payload !== 'string' || payload.length > 200) return null;
  const parts = payload.split('|');
  if (parts.length !== 3 || parts[0] !== QR_PREFIX) return null;
  const expected = Buffer.from(questSig(parts[1]));
  const sent = Buffer.from(parts[2]);
  return sent.length === expected.length && crypto.timingSafeEqual(sent, expected) ? parts[1] : null;
}

/** Today's date in Thailand (UTC+7) as YYYY-MM-DD: quest dates are whole days in Thai time, end date inclusive. */
function bangkokToday(now = Date.now()) {
  return new Date(now + 7 * 3600 * 1000).toISOString().slice(0, 10);
}

function validDate(s) {
  return typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`)) &&
    new Date(`${s}T00:00:00Z`).toISOString().slice(0, 10) === s;
}

/** upcoming | active | ended for an approved quest. */
function questPhase(quest, today = bangkokToday()) {
  if (quest.permanent) return 'active';
  if (today < quest.start_date) return 'upcoming';
  if (today > quest.end_date) return 'ended';
  return 'active';
}

/** Checks a JPEG data URL (what the app's resizer produces) and its size; returns an error string or null. */
function imageError(value, maxChars, label) {
  if (typeof value !== 'string' || !/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(value)) return `${label}ต้องเป็นไฟล์ภาพ JPEG`;
  if (value.length > maxChars) return `${label}ใหญ่เกินไป`;
  const head = Buffer.from(value.slice('data:image/jpeg;base64,'.length, 'data:image/jpeg;base64,'.length + 8), 'base64');
  if (head[0] !== 0xff || head[1] !== 0xd8) return `${label}ไม่ใช่ไฟล์ JPEG ที่ถูกต้อง`;
  return null;
}

module.exports = { QR_PREFIX, MAX_COVER_CHARS, MAX_CARD_IMAGE_CHARS, questSig, questPayload, parseQuestPayload, bangkokToday, validDate, questPhase, imageError };
