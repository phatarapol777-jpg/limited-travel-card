const BASE_URL = 'https://booking-com.p.rapidapi.com';
const HOST = 'booking-com.p.rapidapi.com';

const destIdCache = new Map();

function apiKey() {
  const key = process.env.RAPIDAPI_KEY;
  if (!key) {
    throw new Error('RapidAPI key not configured. Set RAPIDAPI_KEY in backend/.env');
  }
  return key;
}

async function bookingGetOnce(path, params) {
  const url = new URL(BASE_URL + path);
  for (const [k, v] of Object.entries(params || {})) {
    if (v !== undefined && v !== null) url.searchParams.set(k, v);
  }
  const res = await fetch(url, {
    headers: {
      'x-rapidapi-host': HOST,
      'x-rapidapi-key': apiKey(),
    },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Booking.com API error ${res.status}: ${text.slice(0, 200)}`);
  }
  return res.json();
}

// The upstream Booking.com wrapper occasionally throws a transient
// "authentication token invalid" error that clears up on immediate retry.
async function bookingGet(path, params) {
  try {
    return await bookingGetOnce(path, params);
  } catch (e) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    return bookingGetOnce(path, params);
  }
}

async function resolveDestId(cityName) {
  if (destIdCache.has(cityName)) return destIdCache.get(cityName);
  const results = await bookingGet('/v1/hotels/locations', { locale: 'en-gb', name: cityName });
  const city = (results || []).find((r) => r.dest_type === 'city') || (results || [])[0];
  if (!city) throw new Error(`ไม่พบเมือง "${cityName}" ในระบบค้นหาที่พัก`);
  destIdCache.set(cityName, city.dest_id);
  return city.dest_id;
}

async function searchHotels({ cityName, checkInDate, checkOutDate, adults }) {
  const destId = await resolveDestId(cityName);
  const data = await bookingGet('/v1/hotels/search', {
    dest_id: destId,
    dest_type: 'city',
    checkin_date: checkInDate,
    checkout_date: checkOutDate,
    adults_number: adults,
    order_by: 'popularity',
    filter_by_currency: 'THB',
    locale: 'en-gb',
    room_number: 1,
    units: 'metric',
    page_number: 0,
  });
  return (data.result || []).filter((h) => h.hotel_id);
}

module.exports = { searchHotels };
