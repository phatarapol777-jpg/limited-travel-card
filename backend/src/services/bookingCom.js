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
// "authentication token invalid" error that clears up on retry.
async function bookingGet(path, params) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await new Promise((resolve) => setTimeout(resolve, 600 * attempt));
    try {
      return await bookingGetOnce(path, params);
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError;
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

async function getHotelPhotos(hotelId) {
  const photos = await bookingGet('/v1/hotels/photos', { hotel_id: hotelId, locale: 'en-gb' });
  return (photos || []).map((p) => ({
    thumb_url: p.url_square60 || null,
    large_url: p.url_max || p.url_1440 || null,
  }));
}

async function getHotelReviews(hotelId) {
  const data = await bookingGet('/v1/hotels/reviews', {
    hotel_id: hotelId,
    locale: 'en-gb',
    sort_type: 'SORT_MOST_RELEVANT',
    language_filter: 'en-gb',
    page_number: 0,
  });
  return (data.result || []).map((r) => ({
    review_id: r.review_id,
    title: r.title || null,
    pros: r.pros || null,
    cons: r.cons || null,
    score: typeof r.average_score === 'number' ? r.average_score : null,
    author_name: r.author?.name || null,
    author_type: r.author?.type_string || null,
    author_country: r.author?.countrycode || null,
    date: r.date || null,
  }));
}

module.exports = { searchHotels, getHotelPhotos, getHotelReviews };
