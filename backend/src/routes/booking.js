const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');
const bookingCom = require('../services/bookingCom');

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
    const { location_id, check_in, check_out, adults } = req.query;
    if (!location_id) return res.status(400).json({ error: 'location_id is required' });

    const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(location_id);
    if (!location) return res.status(404).json({ error: 'Location not found' });
    if (!location.city_code) return res.status(400).json({ error: 'ไม่มีข้อมูลเมืองสำหรับสถานที่นี้' });

    const checkInDate = check_in || defaultCheckIn();
    const checkOutDate = check_out || defaultCheckOut(checkInDate);
    const numAdults = parseInt(adults, 10) || 2;

    const hotelsList = await bookingCom.searchHotels({ cityName: location.city_code, checkInDate, checkOutDate, adults: numAdults });

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
        hotel_name: hotelName,
        price_amount: priceAmount,
        price_currency: currency,
        room_description: roomDescription,
      });
    }

    res.json({ search_id: searchId, city_code: location.city_code, check_in_date: checkInDate, check_out_date: checkOutDate, hotels: results });
  } catch (err) {
    res.status(502).json({ error: err.message || 'Failed to fetch hotel data' });
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
  const rows = db.prepare(`SELECT br.*, ho.room_description, ho.price_amount, ho.price_currency, ho.check_in_date, ho.check_out_date, h.name AS hotel_name
    FROM booking_requests br
    JOIN hotel_offers ho ON ho.offer_id = br.offer_id
    JOIN hotels h ON h.hotel_id = ho.hotel_id
    WHERE br.user_id = ? ORDER BY br.requested_at DESC`).all(req.user.user_id);
  res.json({ requests: rows });
});

module.exports = router;
