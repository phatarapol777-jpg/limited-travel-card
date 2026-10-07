const db = require('../db');

// Switches and numbers an admin can change from the dashboard. They live in the database, so they survive restarts and
// backup restores. Environment variables only provide the first value (the default) before anyone has changed it.
const DEFINITIONS = {
  env_check: {
    type: 'bool',
    label: 'ตรวจว่ามือถืออยู่ใกล้ตู้ (เครือข่ายเดียวกัน หรือ GPS) ตอนเช็คอินที่ตู้',
    default: () => String(process.env.ENV_CHECK || 'on').toLowerCase() !== 'off',
  },
  kiosk_geo_radius_m: {
    type: 'number', min: 50, max: 5000,
    label: 'รัศมีที่ถือว่า "ใกล้ตู้" (เมตร)',
    default: () => parseInt(process.env.KIOSK_GEO_RADIUS_M, 10) || 300,
  },
  quest_geo_check: {
    type: 'bool',
    label: 'ตรวจ GPS ตอนสแกน QR ภารกิจ (ต้องอยู่ใกล้สถานที่)',
    default: () => String(process.env.QUEST_GEO_CHECK || 'on').toLowerCase() !== 'off',
  },
  community_tag_verify: {
    type: 'bool',
    label: 'นับสถานที่ที่แท็กในโพสต์เข้าอันดับประจำเดือน เฉพาะที่ผู้ใช้เคยเช็กอินจริงหรือมีการ์ดสถานที่นั้น (กันการแท็กมั่ว)',
    default: () => String(process.env.COMMUNITY_TAG_VERIFY || 'off').toLowerCase() === 'on',
  },
  community_badge_top_n: {
    type: 'number', min: 1, max: 10,
    label: 'จำนวนอันดับสูงสุดที่ได้รับตราสัญลักษณ์ประจำเดือน',
    default: () => parseInt(process.env.COMMUNITY_BADGE_TOP_N, 10) || 3,
  },
  quest_geo_radius_m: {
    type: 'number', min: 100, max: 20000,
    label: 'รัศมีรอบสถานที่สำหรับสแกนภารกิจ (เมตร)',
    default: () => parseInt(process.env.QUEST_GEO_RADIUS_M, 10) || 1000,
  },
};

function raw(key) {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key);
  return row ? row.value : undefined;
}

function get(key) {
  const def = DEFINITIONS[key];
  if (!def) throw new Error(`unknown setting ${key}`);
  const stored = raw(key);
  if (stored === undefined) return def.default();
  return def.type === 'bool' ? stored === 'true' : Number(stored);
}

function all() {
  return Object.entries(DEFINITIONS).map(([key, def]) => ({
    key, label: def.label, type: def.type, min: def.min, max: def.max, value: get(key), default: def.default(), changed: raw(key) !== undefined,
  }));
}

/** Validates and stores one setting; returns an error message or null. */
function set(key, value) {
  const def = DEFINITIONS[key];
  if (!def) return 'ไม่รู้จักการตั้งค่านี้';
  let text;
  if (def.type === 'bool') {
    if (typeof value !== 'boolean') return 'ค่าต้องเป็น เปิด/ปิด';
    text = String(value);
  } else {
    const n = Number(value);
    if (!Number.isFinite(n) || !Number.isInteger(n) || n < def.min || n > def.max) return `ใส่จำนวนเต็ม ${def.min} ถึง ${def.max}`;
    text = String(n);
  }
  db.prepare(`INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`).run(key, text, new Date().toISOString());
  return null;
}

module.exports = { get, set, all, DEFINITIONS };
