const db = require('../db');
const { newId } = require('../util');
const { bangkokToday, validDate } = require('./questService');

const CATEGORIES = ['RESTAURANT', 'CAFE', 'SOUVENIR', 'ACCOMMODATION', 'ACTIVITY'];
const STATUSES = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'];
const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

// The database is backed up whole after every change, and JPEGs do not compress, so every image has a hard cap.
// A shop with every slot filled stays under about 0.8 MB (cover 120 KB + 5 gallery 50 KB + 8 items 50 KB).
const MAX_COVER_CHARS = 165_000; // ~120 KB
const MAX_SMALL_IMAGE_CHARS = 60_000; // ~45 KB
const MAX_GALLERY = 5;
const MAX_ITEMS = 8;
const MAX_PRIVILEGES = 5;
const MAX_SHOPS_PER_USER = 10;
const MAX_PENDING_PER_USER = 5;

// A sanity box around Thailand: stops a mistyped coordinate (a missing decimal point, swapped fields) putting a shop off the map.
const THAI_BOUNDS = { latMin: 5, latMax: 21, lngMin: 97, lngMax: 106 };

function imageProblem(value, maxChars, label) {
  if (typeof value !== 'string' || !/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(value)) return `${label}ต้องเป็นไฟล์ภาพ JPEG`;
  if (value.length > maxChars) return `${label}ใหญ่เกินไป (ย่อภาพให้เล็กลง)`;
  const head = Buffer.from(value.slice('data:image/jpeg;base64,'.length, 'data:image/jpeg;base64,'.length + 8), 'base64');
  if (head[0] !== 0xff || head[1] !== 0xd8) return `${label}ไม่ใช่ไฟล์ JPEG ที่ถูกต้อง`;
  return null;
}

// ---- opening hours -----------------------------------------------------------------------------------------------------
// {"mon": [["09:00","18:00"]], "tue": [], ...}  seven keys, up to 3 ranges a day, a range whose end is earlier than its
// start runs past midnight into the next day (e.g. 18:00 to 02:00).
const toMinutes = (t) => {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(t);
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};

function validateHours(hours) {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return { error: 'กรอกเวลาทำการ' };
  const clean = {};
  for (const day of DAYS) {
    const ranges = hours[day] === undefined ? [] : hours[day];
    if (!Array.isArray(ranges) || ranges.length > 3) return { error: 'เวลาทำการแต่ละวันใส่ได้ไม่เกิน 3 ช่วง' };
    clean[day] = [];
    for (const r of ranges) {
      if (!Array.isArray(r) || r.length !== 2) return { error: 'รูปแบบเวลาทำการไม่ถูกต้อง' };
      const a = toMinutes(r[0]);
      const b = toMinutes(r[1]);
      if (a === null || b === null || a === b) return { error: 'เวลาเปิด-ปิดต้องเป็น HH:MM และไม่เท่ากัน' };
      clean[day].push([r[0], r[1]]);
    }
  }
  return { hours: clean };
}

/** Is the shop open at this moment (Thai time)? `now` is a timestamp in ms. */
function isOpenNow(hours, now = Date.now()) {
  if (!hours) return false;
  const t = new Date(now + 7 * 3600 * 1000);
  const minute = t.getUTCHours() * 60 + t.getUTCMinutes();
  const today = DAYS[t.getUTCDay()];
  const yesterday = DAYS[(t.getUTCDay() + 6) % 7];
  for (const [from, to] of hours[today] || []) {
    const a = toMinutes(from);
    const b = toMinutes(to);
    if (b > a ? minute >= a && minute < b : minute >= a) return true; // a range ending after midnight is open until the end of today here
  }
  for (const [from, to] of hours[yesterday] || []) {
    const a = toMinutes(from);
    const b = toMinutes(to);
    if (b < a && minute < b) return true; // yesterday's late-night range spilling into this morning
  }
  return false;
}

function todayHoursText(hours, now = Date.now()) {
  const t = new Date(now + 7 * 3600 * 1000);
  const ranges = (hours && hours[DAYS[t.getUTCDay()]]) || [];
  return ranges.length ? ranges.map(([a, b]) => `${a} - ${b}`).join(', ') : 'ปิดทำการวันนี้';
}

// ---- form validation ---------------------------------------------------------------------------------------------------
const phoneOk = (v) => /^[0-9+\-\s()]{6,20}$/.test(v);
const httpUrl = (v) => /^https?:\/\/[^\s]{3,190}$/.test(v);
const lineOk = (v) => /^(https?:\/\/[^\s]{3,190}|@[A-Za-z0-9._-]{2,40})$/.test(v);

/** The public cards a shop may attach a perk to: location cards, approved quest cards, and physical-pack designs. */
function publicTemplateIds() {
  return new Set(db.prepare(`SELECT t.template_id FROM card_templates t LEFT JOIN quests q ON q.quest_id = t.quest_id
    WHERE (t.quest_id IS NULL AND (t.card_type = 'QUEST_LOCATION' OR EXISTS (SELECT 1 FROM all_cards c WHERE c.template_id = t.template_id AND c.activation_code IS NOT NULL)))
       OR q.status IN ('approved', 'closed')`).all().map((r) => r.template_id));
}

/** Validates the whole shop form (images included). Returns {error} or {form} with cleaned values. */
function parseMerchantForm(b) {
  const nameTh = String(b.shop_name_th || '').trim();
  const nameEn = String(b.shop_name_en || '').trim();
  const description = String(b.description || '').trim();
  const address = String(b.address_detail || '').trim();
  if (!nameTh || nameTh.length > 80) return { error: 'กรอกชื่อร้านภาษาไทย (ไม่เกิน 80 ตัวอักษร)' };
  if (!nameEn || nameEn.length > 80) return { error: 'กรอกชื่อร้านภาษาอังกฤษ (ไม่เกิน 80 ตัวอักษร)' };
  if (!CATEGORIES.includes(b.category)) return { error: 'เลือกหมวดหมู่ร้านค้า' };
  if (!description || description.length > 1000) return { error: 'กรอกคำอธิบายร้านค้า (ไม่เกิน 1,000 ตัวอักษร)' };
  if (!address || address.length > 300) return { error: 'กรอกที่อยู่ร้านค้า (ไม่เกิน 300 ตัวอักษร)' };

  const lat = Number(b.latitude);
  const lng = Number(b.longitude);
  if (b.latitude === null || b.latitude === '' || b.longitude === null || b.longitude === '' || !Number.isFinite(lat) || !Number.isFinite(lng)) {
    return { error: 'ปักหมุดตำแหน่งร้านบนแผนที่' };
  }
  if (lat < THAI_BOUNDS.latMin || lat > THAI_BOUNDS.latMax || lng < THAI_BOUNDS.lngMin || lng > THAI_BOUNDS.lngMax) {
    return { error: 'ตำแหน่งอยู่นอกประเทศไทย กรุณาตรวจสอบพิกัดอีกครั้ง' };
  }
  let nearby = null;
  if (b.nearby_location_id) {
    if (!db.prepare('SELECT 1 FROM locations WHERE location_id = ?').get(b.nearby_location_id)) return { error: 'ไม่พบสถานที่ท่องเที่ยวใกล้เคียงที่เลือก' };
    nearby = b.nearby_location_id;
  }

  const hours = validateHours(b.opening_hours);
  if (hours.error) return { error: hours.error };

  const phone = String(b.phone || '').trim();
  if (!phone || !phoneOk(phone)) return { error: 'กรอกเบอร์โทรศัพท์ให้ถูกต้อง' };
  const social = {};
  for (const [key, check, label] of [['facebook', httpUrl, 'Facebook'], ['instagram', httpUrl, 'Instagram'], ['line', lineOk, 'LINE']]) {
    const v = String(b[key] || '').trim();
    if (v && !check(v)) return { error: `ลิงก์ ${label} ไม่ถูกต้อง (ต้องขึ้นต้นด้วย https://${key === 'line' ? ' หรือเป็น @ไอดี' : ''})` };
    social[key] = v || null;
  }

  const coverErr = imageProblem(b.cover_image, MAX_COVER_CHARS, 'ภาพปกร้าน');
  if (coverErr) return { error: coverErr };

  const galleryIn = Array.isArray(b.gallery) ? b.gallery : [];
  if (galleryIn.length > MAX_GALLERY) return { error: `ภาพบรรยากาศใส่ได้สูงสุด ${MAX_GALLERY} ภาพ` };
  const gallery = [];
  for (const g of galleryIn) {
    const err = imageProblem(g && g.image, MAX_SMALL_IMAGE_CHARS, 'ภาพบรรยากาศ');
    if (err) return { error: err };
    gallery.push(g.image);
  }

  const itemsIn = Array.isArray(b.items) ? b.items : [];
  if (itemsIn.length > MAX_ITEMS) return { error: `เมนู/สินค้าแนะนำใส่ได้สูงสุด ${MAX_ITEMS} รายการ` };
  const items = [];
  for (const it of itemsIn) {
    const name = String((it && it.name) || '').trim();
    if (!name || name.length > 80) return { error: 'ทุกรายการแนะนำต้องมีชื่อ (ไม่เกิน 80 ตัวอักษร)' };
    let price = null;
    if (it.price !== null && it.price !== undefined && it.price !== '') {
      price = Number(it.price);
      if (!Number.isFinite(price) || price < 0 || price > 1_000_000) return { error: 'ราคาต้องเป็นตัวเลข 0 ถึง 1,000,000' };
    }
    const err = imageProblem(it.image, MAX_SMALL_IMAGE_CHARS, `ภาพของ "${name}"`);
    if (err) return { error: err };
    items.push({ name, price, image: it.image, is_signature: it.is_signature === true });
  }

  const privIn = Array.isArray(b.privileges) ? b.privileges : [];
  if (privIn.length > MAX_PRIVILEGES) return { error: `ผูกสิทธิประโยชน์ได้สูงสุด ${MAX_PRIVILEGES} รายการ` };
  const allowed = publicTemplateIds();
  const privileges = [];
  const seen = new Set();
  for (const p of privIn) {
    if (!p || !allowed.has(p.template_id)) return { error: 'เลือกการ์ดสำหรับสิทธิประโยชน์ไม่ถูกต้อง' };
    if (seen.has(p.template_id)) return { error: 'การ์ดใบเดียวกันผูกสิทธิประโยชน์ซ้ำกันไม่ได้' };
    seen.add(p.template_id);
    const text = String(p.description || '').trim();
    if (!text || text.length > 300) return { error: 'กรอกรายละเอียดสิทธิประโยชน์ (ไม่เกิน 300 ตัวอักษร)' };
    const hasStart = p.start_date !== null && p.start_date !== undefined && p.start_date !== '';
    const hasEnd = p.end_date !== null && p.end_date !== undefined && p.end_date !== '';
    if (hasStart !== hasEnd) return { error: 'ระบุทั้งวันเริ่มและวันสิ้นสุดของโปรโมชัน หรือเว้นว่างทั้งคู่ (ไม่มีวันหมดอายุ)' };
    if (hasStart) {
      if (!validDate(p.start_date) || !validDate(p.end_date)) return { error: 'วันที่โปรโมชันไม่ถูกต้อง' };
      if (p.end_date < p.start_date) return { error: 'วันสิ้นสุดโปรโมชันต้องไม่ก่อนวันเริ่ม' };
      if (p.end_date < bangkokToday()) return { error: 'วันสิ้นสุดโปรโมชันผ่านมาแล้ว' };
    }
    privileges.push({ template_id: p.template_id, description: text, start_date: hasStart ? p.start_date : null, end_date: hasEnd ? p.end_date : null });
  }

  return {
    form: {
      shop_name_th: nameTh, shop_name_en: nameEn, category: b.category, description, address_detail: address,
      latitude: lat, longitude: lng, nearby_location_id: nearby, opening_hours: hours.hours, phone, ...social,
      cover_image: b.cover_image, gallery, items, privileges,
    },
  };
}

// ---- reading and writing a shop ---------------------------------------------------------------------------------------------
/** Writes a validated form into the live tables (replacing the gallery, items and perks). */
const applyForm = db.transaction((merchantId, form) => {
  db.prepare(`UPDATE merchants SET shop_name_th = ?, shop_name_en = ?, category = ?, description = ?, address_detail = ?, latitude = ?, longitude = ?,
      nearby_location_id = ?, opening_hours = ?, phone = ?, facebook = ?, instagram = ?, line = ?, cover_image = ?, updated_at = ? WHERE merchant_id = ?`)
    .run(form.shop_name_th, form.shop_name_en, form.category, form.description, form.address_detail, form.latitude, form.longitude,
      form.nearby_location_id, JSON.stringify(form.opening_hours), form.phone, form.facebook, form.instagram, form.line, form.cover_image,
      new Date().toISOString(), merchantId);
  db.prepare('DELETE FROM merchant_gallery WHERE merchant_id = ?').run(merchantId);
  db.prepare('DELETE FROM merchant_items WHERE merchant_id = ?').run(merchantId);
  db.prepare('DELETE FROM merchant_privileges WHERE merchant_id = ?').run(merchantId);
  form.gallery.forEach((image, i) => db.prepare('INSERT INTO merchant_gallery (image_id, merchant_id, position, image) VALUES (?, ?, ?, ?)').run(newId('mgl'), merchantId, i, image));
  form.items.forEach((it, i) => db.prepare('INSERT INTO merchant_items (item_id, merchant_id, position, name, price, image, is_signature) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .run(newId('mit'), merchantId, i, it.name, it.price, it.image, it.is_signature ? 1 : 0));
  form.privileges.forEach((p) => db.prepare('INSERT INTO merchant_privileges (privilege_id, merchant_id, template_id, description, start_date, end_date) VALUES (?, ?, ?, ?, ?, ?)')
    .run(newId('prv'), merchantId, p.template_id, p.description, p.start_date, p.end_date));
});

/** The live content of a shop as a form (every image embedded as a data URL), for editing and for admin review. */
function liveForm(merchantId) {
  const m = db.prepare('SELECT * FROM merchants WHERE merchant_id = ?').get(merchantId);
  return {
    shop_name_th: m.shop_name_th, shop_name_en: m.shop_name_en, category: m.category, description: m.description, address_detail: m.address_detail,
    latitude: m.latitude, longitude: m.longitude, nearby_location_id: m.nearby_location_id, opening_hours: JSON.parse(m.opening_hours),
    phone: m.phone, facebook: m.facebook, instagram: m.instagram, line: m.line, cover_image: m.cover_image,
    gallery: db.prepare('SELECT image FROM merchant_gallery WHERE merchant_id = ? ORDER BY position').all(merchantId).map((r) => ({ image: r.image })),
    items: db.prepare('SELECT name, price, image, is_signature FROM merchant_items WHERE merchant_id = ? ORDER BY position').all(merchantId)
      .map((r) => ({ name: r.name, price: r.price, image: r.image, is_signature: !!r.is_signature })),
    privileges: db.prepare('SELECT template_id, description, start_date, end_date FROM merchant_privileges WHERE merchant_id = ? ORDER BY rowid').all(merchantId),
  };
}

/** What is being reviewed / edited: the waiting revision if there is one, otherwise the live content. */
function currentForm(merchantId) {
  const m = db.prepare('SELECT pending_revision FROM merchants WHERE merchant_id = ?').get(merchantId);
  return m.pending_revision ? JSON.parse(m.pending_revision) : liveForm(merchantId);
}

const PUBLIC_COLUMNS = `m.merchant_id, m.shop_name_th, m.shop_name_en, m.category, m.latitude, m.longitude, m.nearby_location_id, m.opening_hours,
  m.updated_at, (m.cover_image IS NOT NULL) AS has_cover`;

function privilegeValid(p, today = bangkokToday()) {
  return (!p.start_date || p.start_date <= today) && (!p.end_date || p.end_date >= today);
}

/** The light card of a shop for the map and lists. */
function lightView(row, privileges, now = Date.now()) {
  const hours = JSON.parse(row.opening_hours);
  const today = bangkokToday(now);
  return {
    merchant_id: row.merchant_id,
    shop_name_th: row.shop_name_th,
    shop_name_en: row.shop_name_en,
    category: row.category,
    latitude: row.latitude,
    longitude: row.longitude,
    nearby_location_id: row.nearby_location_id,
    has_cover: !!row.has_cover,
    rev: row.updated_at,
    open_now: isOpenNow(hours, now),
    has_privilege: privileges.some((p) => privilegeValid(p, today)),
  };
}

const LEGACY_CATEGORY = { restaurant: 'RESTAURANT', local_cafe: 'CAFE', store: 'SOUVENIR', checkroom: 'SOUVENIR', pedal_bike: 'ACTIVITY' };

/**
 * The first version listed five partner shops in a read-only table. Turn each into an approved merchant exactly once
 * (legacy_shop_id is unique), owned by the first admin. Runs after seeding on every boot, which is safe after a restore too.
 */
function migrateLegacyShops() {
  const admin = db.prepare('SELECT user_id FROM users WHERE is_admin = 1 ORDER BY rowid LIMIT 1').get();
  if (!admin) return 0;
  const week = JSON.stringify(Object.fromEntries(DAYS.map((d) => [d, [['09:00', '18:00']]])));
  const now = new Date().toISOString();
  let added = 0;
  const rows = db.prepare(`SELECT s.*, l.name AS location_name, l.province, l.latitude, l.longitude FROM shops s
    JOIN locations l ON l.location_id = s.location_id WHERE NOT EXISTS (SELECT 1 FROM merchants m WHERE m.legacy_shop_id = s.shop_id)`).all();
  for (const r of rows) {
    db.prepare(`INSERT INTO merchants (merchant_id, owner_user_id, shop_name_th, shop_name_en, category, description, latitude, longitude, address_detail,
        nearby_location_id, opening_hours, approval_status, legacy_shop_id, created_at, updated_at, reviewed_at)
      VALUES (?, ?, ?, ?, ?, 'ร้านค้าพันธมิตรในพื้นที่', ?, ?, ?, ?, ?, 'APPROVED', ?, ?, ?, ?)`)
      .run(newId('mrc'), admin.user_id, r.shop_name, r.shop_name, LEGACY_CATEGORY[r.icon] || 'SOUVENIR', r.latitude, r.longitude,
        `${r.location_name} ${r.province}`, r.location_id, week, r.shop_id, now, now, now);
    added += 1;
  }
  return added;
}

module.exports = {
  migrateLegacyShops, CATEGORIES, STATUSES, DAYS, MAX_GALLERY, MAX_ITEMS, MAX_PRIVILEGES, MAX_SHOPS_PER_USER, MAX_PENDING_PER_USER, MAX_COVER_CHARS, MAX_SMALL_IMAGE_CHARS,
  THAI_BOUNDS, validateHours, isOpenNow, todayHoursText, parseMerchantForm, applyForm, liveForm, currentForm, publicTemplateIds,
  PUBLIC_COLUMNS, privilegeValid, lightView, imageProblem,
};
