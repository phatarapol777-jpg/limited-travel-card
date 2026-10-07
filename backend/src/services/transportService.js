const { bookingGet } = require('./bookingCom');

// Flights and rental cars come from the same Booking.com (RapidAPI) wrapper as the hotels. Searches use up quota, so identical
// searches are answered from memory for a few minutes.
const CACHE_MS = 5 * 60 * 1000;
const cache = new Map();

async function cached(key, load) {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.value;
  const value = await load();
  cache.set(key, { at: Date.now(), value });
  if (cache.size > 200) cache.delete(cache.keys().next().value); // oldest first
  return value;
}

const money = (m) => (m && Number.isFinite(m.units) ? Math.round((m.units + (m.nanos || 0) / 1e9) * 100) / 100 : null);
const minutes = (seconds) => (Number.isFinite(seconds) ? Math.round(seconds / 60) : null);

function airport(a) {
  return a ? { code: a.code, name: a.name, city: a.cityName || a.city || null, country: a.countryName || null } : null;
}

function segmentView(seg) {
  const legs = seg.legs || [];
  const carriers = new Map();
  for (const leg of legs) for (const c of leg.carriersData || []) carriers.set(c.code, { code: c.code, name: c.name, logo: c.logo || null });
  const luggage = (seg.travellerCheckedLuggage || [])[0];
  return {
    from: airport(seg.departureAirport),
    to: airport(seg.arrivalAirport),
    departure: seg.departureTime,
    arrival: seg.arrivalTime,
    duration_min: minutes(seg.totalTime),
    stops: Math.max(0, legs.length - 1),
    carriers: [...carriers.values()],
    flights: legs.map((l) => {
      const info = l.flightInfo || {};
      const carrier = (info.carrierInfo && (info.carrierInfo.marketingCarrier || info.carrierInfo.operatingCarrier)) || '';
      return { number: `${carrier}${info.flightNumber || ''}`, from: l.departureAirport && l.departureAirport.code, to: l.arrivalAirport && l.arrivalAirport.code, departure: l.departureTime, arrival: l.arrivalTime };
    }),
    cabin: (legs[0] && legs[0].cabinClass) || null,
    checked_bag_kg: luggage && luggage.maxWeightPerPiece ? luggage.maxWeightPerPiece : null,
    checked_bag_pieces: luggage && luggage.maxPiece ? luggage.maxPiece : 0,
  };
}

function flightView(offer) {
  const price = offer.priceBreakdown || {};
  return {
    price: money(price.total),
    currency: (price.total && price.total.currencyCode) || 'THB',
    segments: (offer.segments || []).map(segmentView),
  };
}

async function searchAirports(query) {
  const rows = await cached(`airports|${query.toLowerCase()}`, () => bookingGet('/v1/flights/locations', { name: query, locale: 'en-gb' }));
  return (Array.isArray(rows) ? rows : []).slice(0, 10).map((r) => ({
    code: r.code, type: r.type, name: r.name, city: r.cityName || r.city || null, country: r.countryName || null,
  }));
}

const CABINS = ['ECONOMY', 'PREMIUM_ECONOMY', 'BUSINESS', 'FIRST'];
const ORDERS = ['BEST', 'CHEAPEST', 'FASTEST'];

async function searchFlights({ from, to, date, returnDate, adults = 1, cabin = 'ECONOMY', order = 'BEST' }) {
  const roundTrip = !!returnDate;
  const params = {
    from_code: from, to_code: to, depart_date: date, adults: String(adults), children: '0',
    flight_type: roundTrip ? 'ROUNDTRIP' : 'ONEWAY', cabin_class: CABINS.includes(cabin) ? cabin : 'ECONOMY',
    order_by: ORDERS.includes(order) ? order : 'BEST', locale: 'en-gb', currency: 'THB', page_number: '0',
  };
  if (roundTrip) params.return_date = returnDate;
  const data = await cached(`flights|${JSON.stringify(params)}`, () => bookingGet('/v1/flights/search', params));
  const offers = (data.flightOffers || []).slice(0, 25).map(flightView).filter((o) => o.price !== null && o.segments.length);
  return { total: (data.aggregation && data.aggregation.totalCount) || offers.length, offers };
}

function carView(item) {
  const c = item.content || {};
  const badges = (c.badges || []).map((b) => b.text).filter((t) => t && t !== 'Ad');
  const pickup = c.location && c.location.pickup;
  const supplier = c.supplier || {};
  const pricing = c.pricing || {};
  const digits = String(pricing.finalPriceDisplay || '').replace(/[^0-9.]/g, '');
  return {
    vehicle_id: c.metadata && c.metadata.vehicleId,
    title: c.title,
    subtitle: c.subtitle || null,
    image: c.imageUrl || null,
    specs: [c.specs, ...((c.vehicleSpecs || []).map((s) => s.text))].filter(Boolean),
    badges,
    pickup: pickup ? [pickup.location, pickup.detail].filter(Boolean).join(' · ') : null,
    supplier: supplier.name || null,
    supplier_rating: supplier.rating ? `${supplier.rating.score} ${supplier.rating.description} (${supplier.rating.reviewCountText})` : null,
    price_text: pricing.finalPriceDisplay || null,
    price: digits ? Number(digits.replace(/,/g, '')) : null,
    duration_text: pricing.durationText || null,
    special_offer: (c.specialOffer && c.specialOffer.text) || null,
  };
}

const CAR_SORTS = ['recommended', 'price_low_to_high', 'review_score'];

async function searchCars({ latitude, longitude, pickUp, dropOff, sort = 'price_low_to_high', driverAge = 30 }) {
  const params = {
    pick_up_latitude: String(latitude), pick_up_longitude: String(longitude), drop_off_latitude: String(latitude), drop_off_longitude: String(longitude),
    pick_up_datetime: `${pickUp} 10:00:00`, drop_off_datetime: `${dropOff} 10:00:00`, from_country: 'th', driver_age: String(driverAge),
    sort_by: CAR_SORTS.includes(sort) ? sort : 'price_low_to_high', units: 'metric', locale: 'en-gb', currency: 'THB',
  };
  const data = await cached(`cars|${JSON.stringify(params)}`, () => bookingGet('/v1/car-rental/search', params));
  const items = ((data.content && data.content.items) || []).filter((i) => i.type === 'CAR_CARD');
  let cars = items.map(carView).filter((c) => c.title);
  // the upstream puts sponsored cars first even when sorted by price, so a price sort is done here
  if (params.sort_by === 'price_low_to_high') cars = cars.sort((a, b) => (a.price ?? Infinity) - (b.price ?? Infinity));
  return { total: items.length, cars: cars.slice(0, 30) };
}

module.exports = { searchAirports, searchFlights, searchCars, CABINS, ORDERS, CAR_SORTS, flightView, carView, _cache: cache };
