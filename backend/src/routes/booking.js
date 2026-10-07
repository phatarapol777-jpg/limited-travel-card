const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const bookingCom = require('../services/bookingCom');
const transport = require('../services/transportService');
const { bangkokToday } = require('../services/questService');

const router = express.Router();

function defaultCheckIn() {
  const d = new Date();
  d.setDate(d.getDate() + 14);
  return d.toISOString().slice(0, 10);
}

function defaultCheckOut(checkIn) {
  const d = new Date(checkIn);
  d.setDate(d.getDate() + 2);
  return d.toISOString().slice(0, 10);
}

function optionalUserId(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return null;
  const session = db.prepare('SELECT user_id FROM sessions WHERE token = ?').get(token);
  return session ? session.user_id : null;
}

router.get('/hotels', async (req, res) => {
  try {
    const { location_id, check_in, check_out, adults, children, children_ages, rooms } = req.query;
    if (!location_id) return res.status(400).json({ error: 'location_id is required' });

    const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(location_id);
    if (!location) return res.status(404).json({ error: 'Location not found' });
    if (!location.city_code) return res.status(400).json({ error: 'ไม่มีข้อมูลเมืองสำหรับสถานที่นี้' });

    const checkInDate = check_in || defaultCheckIn();
    const checkOutDate = check_out || defaultCheckOut(checkInDate);
    const numAdults = parseInt(adults, 10) || 2;
    const numChildren = parseInt(children, 10) || 0;
    const numRooms = parseInt(rooms, 10) || 1;

    const hotelsList = await bookingCom.searchHotels({
      cityName: location.city_code, checkInDate, checkOutDate,
      adults: numAdults, children: numChildren, childrenAges: children_ages || '10', rooms: numRooms,
    });

    const now = new Date().toISOString();
    const searchId = newId('srch');
    db.prepare(`INSERT INTO hotel_searches (search_id, user_id, location_id, city_code, check_in_date, check_out_date, adults, searched_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(searchId, optionalUserId(req), location_id, location.city_code, checkInDate, checkOutDate, numAdults, now);

    const findHotel = db.prepare('SELECT * FROM hotels WHERE external_hotel_id = ?');
    const insertHotel = db.prepare(`INSERT INTO hotels (hotel_id, external_hotel_id, name, city_code, location_id, latitude, longitude, cached_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`);
    const insertOffer = db.prepare(`INSERT INTO hotel_offers
      (offer_id, search_id, hotel_id, external_offer_id, room_description, price_amount, price_currency, check_in_date, check_out_date, raw_json, cached_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);

    const results = [];
    for (const h of hotelsList.slice(0, 15)) {
      const externalHotelId = String(h.hotel_id);
      let hotelRow = findHotel.get(externalHotelId);
      let hotelId;
      const hotelName = h.hotel_name_trans || h.hotel_name || 'ไม่ทราบชื่อโรงแรม';
      if (hotelRow) {
        hotelId = hotelRow.hotel_id;
      } else {
        hotelId = newId('htl');
        insertHotel.run(hotelId, externalHotelId, hotelName, location.city_code, location_id, h.latitude ?? null, h.longitude ?? null, now);
      }
      const offerId = newId('ofr');
      const priceAmount = typeof h.min_total_price === 'number' ? h.min_total_price : null;
      const currency = h.currencycode || h.currency_code || 'THB';
      const roomDescription = [
        h.class ? `${h.class}★` : null,
        typeof h.review_score === 'number' ? `รีวิว ${h.review_score}/10` : null,
        h.distance_to_cc_formatted ? `ห่างจากใจกลางเมือง ${h.distance_to_cc_formatted}` : null,
      ].filter(Boolean).join(' · ') || null;
      insertOffer.run(
        offerId, searchId, hotelId, externalHotelId,
        roomDescription, priceAmount, currency,
        checkInDate, checkOutDate, JSON.stringify(h), now,
      );
      results.push({
        offer_id: offerId,
        external_hotel_id: externalHotelId,
        hotel_name: hotelName,
        price_amount: priceAmount,
        price_currency: currency,
        room_description: roomDescription,
        photo_url: h.main_photo_url || null,
        large_photo_url: h.max_photo_url || h.main_photo_url || null,
        address: [h.address, h.district, h.city_trans].filter(Boolean).join(', ') || null,
        star_class: typeof h.class === 'number' ? h.class : null,
        review_score: typeof h.review_score === 'number' ? h.review_score : null,
        review_score_word: h.review_score_word || null,
        review_count: typeof h.review_nr === 'number' ? h.review_nr : null,
        distance_to_center: h.distance_to_cc_formatted || null,
        booking_url: h.url || null,
        latitude: typeof h.latitude === 'number' ? h.latitude : null,
        longitude: typeof h.longitude === 'number' ? h.longitude : null,
        has_free_parking: h.has_free_parking === 1,
        has_swimming_pool: h.has_swimming_pool === 1,
        include_breakfast: h.hotel_include_breakfast === 1,
      });
    }

    res.json({ search_id: searchId, city_code: location.city_code, check_in_date: checkInDate, check_out_date: checkOutDate, hotels: results });
  } catch (err) {
    res.status(502).json({ error: err.message || 'Failed to fetch hotel data' });
  }
});

router.get('/hotels/:externalHotelId/photos', async (req, res) => {
  try {
    const photos = await bookingCom.getHotelPhotos(req.params.externalHotelId);
    res.json({ photos: photos.slice(0, 12) });
  } catch (err) {
    res.status(502).json({ error: err.message || 'Failed to fetch hotel photos' });
  }
});

router.get('/hotels/:externalHotelId/reviews', async (req, res) => {
  try {
    const reviews = await bookingCom.getHotelReviews(req.params.externalHotelId);
    res.json({ reviews: reviews.slice(0, 10) });
  } catch (err) {
    res.status(502).json({ error: err.message || 'Failed to fetch hotel reviews' });
  }
});

router.post('/request', authMiddleware, (req, res) => {
  const { offer_id, guest_name } = req.body || {};
  const offer = db.prepare('SELECT * FROM hotel_offers WHERE offer_id = ?').get(offer_id);
  if (!offer) return res.status(404).json({ error: 'ไม่พบข้อเสนอนี้ (อาจหมดอายุ ลองค้นหาใหม่)' });

  const id = newId('bkr');
  db.prepare(`INSERT INTO booking_requests (booking_request_id, user_id, offer_id, guest_name, status, requested_at)
    VALUES (?, ?, ?, ?, ?, ?)`)
    .run(id, req.user.user_id, offer_id, guest_name || `${req.user.first_name} ${req.user.last_name}`, 'requested', new Date().toISOString());
  res.status(201).json({ booking_request_id: id, status: 'requested' });
});

router.get('/requests', authMiddleware, (req, res) => {
  const rows = db.prepare(`SELECT br.*, ho.room_description, ho.price_amount, ho.price_currency, ho.check_in_date, ho.check_out_date, ho.raw_json, h.name AS hotel_name
    FROM booking_requests br
    JOIN hotel_offers ho ON ho.offer_id = br.offer_id
    JOIN hotels h ON h.hotel_id = ho.hotel_id
    WHERE br.user_id = ? ORDER BY br.requested_at DESC`).all(req.user.user_id);
  const enriched = rows.map((row) => {
    const { raw_json, ...rest } = row;
    let h = {};
    try { h = raw_json ? JSON.parse(raw_json) : {}; } catch (e) { h = {}; }
    return { ...rest, photo_url: h.main_photo_url || null, address: [h.address, h.district, h.city_trans].filter(Boolean).join(', ') || null };
  });
  res.json({ requests: enriched });
});

// ---- flights and rental cars -----------------------------------------------------------------------------------------------------
const isDate = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(`${v}T00:00:00Z`)) && new Date(`${v}T00:00:00Z`).toISOString().slice(0, 10) === v;
const addDays = (ymd, n) => new Date(Date.parse(`${ymd}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);
const AIRPORT_CODE = /^[A-Z]{3}(\.(AIRPORT|CITY))?$/;
const upstream = (res, err) => {
  const m = String(err && err.message || '');
  if (/429|Too many/i.test(m)) return res.status(503).json({ error: 'บริการค้นหาถูกใช้งานหนาแน่น กรุณารอสักครู่แล้วลองใหม่' });
  res.status(502).json({ error: 'ค้นหาไม่สำเร็จ ลองใหม่อีกครั้ง' });
};

router.get('/airports', authMiddleware, async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 2 || q.length > 40) return res.json({ airports: [] });
  try {
    res.json({ airports: await transport.searchAirports(q) });
  } catch (err) {
    upstream(res, err);
  }
});

router.get('/flights', authMiddleware, async (req, res) => {
  const q = req.query;
  const today = bangkokToday();
  if (!AIRPORT_CODE.test(String(q.from)) || !AIRPORT_CODE.test(String(q.to))) return res.status(400).json({ error: 'เลือกต้นทางและปลายทาง' });
  if (q.from === q.to) return res.status(400).json({ error: 'ต้นทางและปลายทางต้องไม่ใช่ที่เดียวกัน' });
  if (!isDate(q.date) || q.date < today || q.date > addDays(today, 365)) return res.status(400).json({ error: 'วันเดินทางไม่ถูกต้อง (ภายใน 1 ปีข้างหน้า)' });
  if (q.return_date && (!isDate(q.return_date) || q.return_date < q.date || q.return_date > addDays(today, 365))) return res.status(400).json({ error: 'วันเดินทางกลับต้องไม่ก่อนวันไป' });
  const adults = parseInt(q.adults, 10) || 1;
  if (adults < 1 || adults > 9) return res.status(400).json({ error: 'จำนวนผู้โดยสารต้อง 1-9 คน' });
  try {
    res.json(await transport.searchFlights({ from: q.from, to: q.to, date: q.date, returnDate: q.return_date || null, adults, cabin: q.cabin, order: q.order }));
  } catch (err) {
    upstream(res, err);
  }
});

router.get('/cars', authMiddleware, async (req, res) => {
  const q = req.query;
  const today = bangkokToday();
  const loc = db.prepare('SELECT latitude, longitude FROM locations WHERE location_id = ?').get(String(q.location_id || ''));
  if (!loc) return res.status(404).json({ error: 'ไม่พบสถานที่' });
  if (!isDate(q.pick_up) || q.pick_up < today || q.pick_up > addDays(today, 365)) return res.status(400).json({ error: 'วันรับรถไม่ถูกต้อง (ภายใน 1 ปีข้างหน้า)' });
  if (!isDate(q.drop_off) || q.drop_off <= q.pick_up || q.drop_off > addDays(q.pick_up, 30)) return res.status(400).json({ error: 'วันคืนรถต้องหลังวันรับรถ และเช่าได้ไม่เกิน 30 วัน' });
  try {
    res.json(await transport.searchCars({ latitude: loc.latitude, longitude: loc.longitude, pickUp: q.pick_up, dropOff: q.drop_off, sort: q.sort }));
  } catch (err) {
    upstream(res, err);
  }
});

// The traveler picks one result and asks to book it. Like the hotel requests, it is only recorded here for an admin to follow up.
router.post('/transport/request', authMiddleware, (req, res) => {
  const b = req.body || {};
  if (!['flight', 'car'].includes(b.kind)) return res.status(400).json({ error: 'ประเภทต้องเป็น flight หรือ car' });
  const title = String(b.title || '').trim();
  if (!title || title.length > 200) return res.status(400).json({ error: 'ข้อมูลที่เลือกไม่ครบ' });
  const summary = JSON.stringify(b.summary && typeof b.summary === 'object' ? b.summary : {});
  if (summary.length > 6000) return res.status(400).json({ error: 'ข้อมูลที่เลือกใหญ่เกินไป' });
  const price = b.price === null || b.price === undefined ? null : Number(b.price);
  if (price !== null && (!Number.isFinite(price) || price < 0 || price > 10_000_000)) return res.status(400).json({ error: 'ราคาไม่ถูกต้อง' });
  const recent = db.prepare('SELECT COUNT(*) AS c FROM transport_requests WHERE user_id = ? AND requested_at >= ?').get(req.user.user_id, new Date(Date.now() - 86400000).toISOString()).c;
  if (recent >= 20) return res.status(429).json({ error: 'ส่งคำขอได้สูงสุด 20 รายการใน 24 ชั่วโมง' });
  const id = newId('trq');
  db.prepare('INSERT INTO transport_requests (request_id, user_id, kind, title, summary_json, price_amount, price_currency, status, requested_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
    .run(id, req.user.user_id, b.kind, title, summary, price, String(b.currency || 'THB').slice(0, 3), 'requested', new Date().toISOString());
  res.status(201).json({ request_id: id, status: 'requested' });
});

router.get('/transport/requests', authMiddleware, (req, res) => {
  const rows = db.prepare('SELECT request_id, kind, title, summary_json, price_amount, price_currency, status, requested_at, cancelled_at FROM transport_requests WHERE user_id = ? ORDER BY requested_at DESC LIMIT 100').all(req.user.user_id);
  res.json({ requests: rows.map(({ summary_json, ...r }) => ({ ...r, summary: JSON.parse(summary_json) })) });
});

// ---- cancelling ------------------------------------------------------------------------------------------------------------------
// A traveler can cancel their own booking while it is waiting or confirmed. The refund is only pretended (the payment page is a demo too).
const CANCELLABLE = ['requested', 'confirmed'];

router.post('/requests/:id/cancel', authMiddleware, (req, res) => {
  const row = db.prepare('SELECT user_id, status FROM booking_requests WHERE booking_request_id = ?').get(req.params.id);
  if (!row || row.user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบการจองนี้' });
  if (!CANCELLABLE.includes(row.status)) return res.status(409).json({ error: row.status === 'cancelled' ? 'การจองนี้ถูกยกเลิกไปแล้ว' : 'การจองนี้ยกเลิกไม่ได้' });
  db.prepare("UPDATE booking_requests SET status = 'cancelled', cancelled_at = ? WHERE booking_request_id = ?").run(new Date().toISOString(), req.params.id);
  res.json({ status: 'cancelled', refund: 'demo' });
});

router.post('/transport/requests/:id/cancel', authMiddleware, (req, res) => {
  const row = db.prepare('SELECT user_id, status FROM transport_requests WHERE request_id = ?').get(req.params.id);
  if (!row || row.user_id !== req.user.user_id) return res.status(404).json({ error: 'ไม่พบการจองนี้' });
  if (!CANCELLABLE.includes(row.status)) return res.status(409).json({ error: row.status === 'cancelled' ? 'การจองนี้ถูกยกเลิกไปแล้ว' : 'การจองนี้ยกเลิกไม่ได้' });
  db.prepare("UPDATE transport_requests SET status = 'cancelled', cancelled_at = ? WHERE request_id = ?").run(new Date().toISOString(), req.params.id);
  res.json({ status: 'cancelled', refund: 'demo' });
});

module.exports = router;
