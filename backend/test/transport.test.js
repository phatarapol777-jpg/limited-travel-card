const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { startServer } = require('./helpers');

// A fake Booking.com upstream with the same response shapes the real one returns (trimmed).
const seen = [];
const airport = (code, name, cityName) => ({ type: 'AIRPORT', code, name, cityName, city: code, countryName: 'Thailand' });
const flightOffer = (price, depart) => ({
  priceBreakdown: { total: { currencyCode: 'THB', units: price, nanos: 490000000 } },
  segments: [{
    departureAirport: airport('BKK', 'Suvarnabhumi Airport', 'Bangkok'), arrivalAirport: airport('CNX', 'Chiang Mai International Airport', 'Chiang Mai'),
    departureTime: `${depart}T10:15:00`, arrivalTime: `${depart}T11:30:00`, totalTime: 4500,
    travellerCheckedLuggage: [{ maxPiece: 1, maxWeightPerPiece: 20 }],
    legs: [{
      departureTime: `${depart}T10:15:00`, arrivalTime: `${depart}T11:30:00`, departureAirport: airport('BKK', 'x', 'Bangkok'), arrivalAirport: airport('CNX', 'y', 'Chiang Mai'),
      cabinClass: 'ECONOMY', flightInfo: { flightNumber: 104, carrierInfo: { marketingCarrier: 'TG', operatingCarrier: 'TG' } },
      carriersData: [{ name: 'Thai Airways', code: 'TG', logo: 'https://example.com/TG.png' }],
    }],
  }],
});
const carCard = (title, price) => ({
  type: 'CAR_CARD',
  content: {
    badges: [{ text: 'Ad' }, { text: 'Free cancellation' }], title, subtitle: 'or similar small car', imageUrl: 'https://example.com/car.png', specs: '5 seats | 4 doors',
    vehicleSpecs: [{ text: 'Automatic' }], location: { pickup: { location: 'Chiang Mai International Airport', detail: 'In Terminal' } },
    supplier: { name: 'Drive Car Rental', rating: { score: '9.1', description: 'Superb', reviewCountText: '617 reviews' } },
    pricing: { finalPriceDisplay: `THB ${price}`, durationText: 'Price for 2 days' }, metadata: { vehicleId: `v-${title}` },
  },
});

let upstream;
let s;
let user;
let adm;
let locId;
const future = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

test.before(async () => {
  upstream = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    seen.push({ path: url.pathname, query: Object.fromEntries(url.searchParams), key: req.headers['x-rapidapi-key'] });
    res.setHeader('content-type', 'application/json');
    if (url.pathname === '/v1/flights/locations') return res.end(JSON.stringify([{ type: 'AIRPORT', name: 'Suvarnabhumi', code: 'BKK.AIRPORT', cityName: 'Bangkok', countryName: 'Thailand' }, { type: 'CITY', name: 'Bangkok', code: 'BKK.CITY', countryName: 'Thailand' }]));
    if (url.pathname === '/v1/flights/search') return res.end(JSON.stringify({ aggregation: { totalCount: 162 }, flightOffers: [flightOffer(2957, url.searchParams.get('depart_date')), { priceBreakdown: {}, segments: [] }] }));
    if (url.pathname === '/v1/car-rental/search') return res.end(JSON.stringify({ content: { items: [{ type: 'INFORMATION_BANNER' }, { type: 'RESULTS_COUNT' }, carCard('Nissan Almera', '1,963'), carCard('Toyota Yaris', '2,100')] } }));
    res.statusCode = 404;
    res.end('{}');
  });
  await new Promise((r) => upstream.listen(0, r));
  s = await startServer({ BOOKING_BASE_URL: `http://localhost:${upstream.address().port}`, RAPIDAPI_KEY: 'test-key' });
  user = await s.register('flyer');
  adm = await s.admin();
  locId = (await s.call('GET', '/catalog/locations')).body.locations[0].location_id;
});
test.after(() => {
  s.stop();
  upstream.close();
});

test('everything needs a sign-in (searches use paid quota)', async () => {
  for (const p of ['/booking/airports?q=bangkok', '/booking/flights?from=BKK&to=CNX', '/booking/cars?location_id=x', '/booking/transport/requests']) {
    assert.equal((await s.call('GET', p)).status, 401, p);
  }
  assert.equal((await s.call('POST', '/booking/transport/request', {})).status, 401);
});

test('airport search', async () => {
  assert.deepEqual((await s.call('GET', '/booking/airports?q=b', undefined, user.token)).body.airports, [], 'too short to search');
  const r = (await s.call('GET', '/booking/airports?q=bangkok', undefined, user.token)).body.airports;
  assert.deepEqual(r.map((a) => a.code), ['BKK.AIRPORT', 'BKK.CITY']);
  assert.equal(seen.at(-1).key, 'test-key');
});

test('flight search: validated, forwarded with the right parameters, and shown in a plain shape', async () => {
  const f = (qs) => s.call('GET', `/booking/flights?${qs}`, undefined, user.token);
  for (const bad of ['', 'from=BKK&to=BKK&date=' + future(10), 'from=BKK.AIRPORT&to=CNX&date=2020-01-01', `from=BKK&to=CNX&date=${future(400)}`, `from=BKK&to=CNX&date=${future(10)}&return_date=${future(5)}`,
    `from=BKK&to=CNX&date=${future(10)}&adults=12`, 'from=bkk&to=CNX&date=' + future(10), `from=BKK&to=CNX&date=2026-02-31`]) {
    assert.equal((await f(bad)).status, 400, bad);
  }
  const date = future(30);
  const r = await f(`from=BKK.AIRPORT&to=CNX.AIRPORT&date=${date}&adults=2&cabin=BUSINESS&order=CHEAPEST`);
  assert.equal(r.status, 200);
  const sent = seen.at(-1);
  assert.equal(sent.path, '/v1/flights/search');
  assert.deepEqual([sent.query.from_code, sent.query.to_code, sent.query.depart_date, sent.query.adults, sent.query.cabin_class, sent.query.order_by, sent.query.flight_type, sent.query.currency],
    ['BKK.AIRPORT', 'CNX.AIRPORT', date, '2', 'BUSINESS', 'CHEAPEST', 'ONEWAY', 'THB']);
  assert.equal(r.body.total, 162);
  assert.equal(r.body.offers.length, 1, 'an offer without a price or segments is dropped');
  const o = r.body.offers[0];
  assert.deepEqual([o.price, o.currency], [2957.49, 'THB']);
  const seg = o.segments[0];
  assert.deepEqual([seg.from.code, seg.to.code, seg.duration_min, seg.stops, seg.flights[0].number, seg.carriers[0].name, seg.checked_bag_kg], ['BKK', 'CNX', 75, 0, 'TG104', 'Thai Airways', 20]);

  const rt = await f(`from=BKK&to=CNX&date=${date}&return_date=${future(35)}`);
  assert.equal(seen.at(-1).query.flight_type, 'ROUNDTRIP');
  assert.equal(seen.at(-1).query.return_date, future(35));
  assert.equal(rt.status, 200);

  const calls = seen.length;
  await f(`from=BKK.AIRPORT&to=CNX.AIRPORT&date=${date}&adults=2&cabin=BUSINESS&order=CHEAPEST`);
  assert.equal(seen.length, calls, 'the same search again is answered from memory');
});

test('rental cars: found from the place coordinates, only real cars are listed', async () => {
  const c = (qs) => s.call('GET', `/booking/cars?${qs}`, undefined, user.token);
  assert.equal((await c(`location_id=nope&pick_up=${future(10)}&drop_off=${future(12)}`)).status, 404);
  for (const bad of [`location_id=${locId}&pick_up=${future(10)}`, `location_id=${locId}&pick_up=${future(10)}&drop_off=${future(10)}`, `location_id=${locId}&pick_up=${future(10)}&drop_off=${future(50)}`,
    `location_id=${locId}&pick_up=2020-01-01&drop_off=2020-01-03`]) {
    assert.equal((await c(bad)).status, 400, bad);
  }
  const r = await c(`location_id=${locId}&pick_up=${future(10)}&drop_off=${future(12)}`);
  assert.equal(r.status, 200);
  const sent = seen.at(-1);
  assert.equal(sent.path, '/v1/car-rental/search');
  assert.ok(Number(sent.query.pick_up_latitude) > 5 && Number(sent.query.pick_up_latitude) < 21);
  assert.equal(sent.query.sort_by, 'price_low_to_high');
  assert.equal(r.body.cars.length, 2, 'banners and counters are not cars');
  assert.deepEqual(r.body.cars.map((x) => x.price), [1963, 2100], 'cheapest first');
  const car = r.body.cars[0];
  assert.deepEqual([car.title, car.price, car.supplier, car.badges], ['Nissan Almera', 1963, 'Drive Car Rental', ['Free cancellation']]);
  assert.match(car.supplier_rating, /9.1 Superb/);
  assert.ok(car.specs.includes('Automatic'));
});

test('an upstream failure is reported kindly, not as a crash', async () => {
  const down = await startServer({ BOOKING_BASE_URL: 'http://localhost:1', RAPIDAPI_KEY: 'k' });
  try {
    const u = await down.register('down');
    const r = await down.call('GET', `/booking/flights?from=BKK&to=CNX&date=${future(10)}`, undefined, u.token);
    assert.equal(r.status, 502);
    assert.match(r.body.error, /ค้นหาไม่สำเร็จ/);
  } finally {
    down.stop();
  }
});

test('requests: recorded for the traveler, listed to the admin who can change the status', async () => {
  const bad = [{}, { kind: 'train', title: 'x' }, { kind: 'flight', title: '' }, { kind: 'flight', title: 'x', price: -1 }, { kind: 'flight', title: 'x', summary: { big: 'x'.repeat(7000) } }];
  for (const b of bad) assert.equal((await s.call('POST', '/booking/transport/request', b, user.token)).status, 400, JSON.stringify(b).slice(0, 50));
  const ok = await s.call('POST', '/booking/transport/request', { kind: 'flight', title: 'BKK → CNX 2026-12-01 · TG104', price: 2957.49, currency: 'THB', summary: { airline: 'Thai Airways' } }, user.token);
  assert.equal(ok.status, 201);
  await s.call('POST', '/booking/transport/request', { kind: 'car', title: 'Nissan Almera', price: 1963 }, user.token);
  const mine = (await s.call('GET', '/booking/transport/requests', undefined, user.token)).body.requests;
  assert.deepEqual(mine.map((r) => [r.kind, r.status]).sort(), [['car', 'requested'], ['flight', 'requested']]);
  assert.equal(mine.find((r) => r.kind === 'flight').summary.airline, 'Thai Airways');
  const other = await s.register('other');
  assert.equal((await s.call('GET', '/booking/transport/requests', undefined, other.token)).body.requests.length, 0);

  assert.equal((await s.call('GET', '/admin/transport-requests', undefined, user.token)).status, 403);
  const all = (await s.call('GET', '/admin/transport-requests', undefined, adm.token)).body.requests;
  assert.equal(all.length, 2);
  assert.equal(all[0].username, user.username);
  assert.equal((await s.call('PUT', `/admin/transport-requests/${ok.body.request_id}/status`, { status: 'confirmed' }, adm.token)).status, 200);
  assert.equal((await s.call('PUT', `/admin/transport-requests/${ok.body.request_id}/status`, { status: 'maybe' }, adm.token)).status, 400);
  assert.equal((await s.call('PUT', '/admin/transport-requests/nope/status', { status: 'confirmed' }, adm.token)).status, 404);
  assert.equal((await s.call('GET', '/booking/transport/requests', undefined, user.token)).body.requests.find((r) => r.kind === 'flight').status, 'confirmed');
});

test('cancelling: only your own booking, only while waiting or confirmed, hotels and flights/cars alike', async () => {
  const me = await s.register('canceller');
  const other = await s.register('bystander');
  const car = await s.call('POST', '/booking/transport/request', { kind: 'car', title: 'Toyota Yaris', price: 1590, summary: { car: { badges: ['Free cancellation'] } } }, me.token);
  const cancel = (id, token = me.token) => s.call('POST', `/booking/transport/requests/${id}/cancel`, {}, token);
  assert.equal((await cancel(car.body.request_id, other.token)).status, 404, 'not yours');
  assert.equal((await cancel('nope')).status, 404);
  assert.equal((await s.call('POST', `/booking/transport/requests/${car.body.request_id}/cancel`, {})).status, 401);
  const done = await cancel(car.body.request_id);
  assert.deepEqual([done.status, done.body.status, done.body.refund], [200, 'cancelled', 'demo']);
  assert.equal((await cancel(car.body.request_id)).status, 409, 'already cancelled');
  const listed = (await s.call('GET', '/booking/transport/requests', undefined, me.token)).body.requests[0];
  assert.deepEqual([listed.status, typeof listed.cancelled_at], ['cancelled', 'string']);
  assert.equal((await s.call('GET', '/admin/transport-requests', undefined, adm.token)).body.requests.find((r) => r.request_id === car.body.request_id).status, 'cancelled');

  // a rejected request cannot be cancelled; a confirmed one can
  const f = await s.call('POST', '/booking/transport/request', { kind: 'flight', title: 'BKK → CNX', price: 1800 }, me.token);
  await s.call('PUT', `/admin/transport-requests/${f.body.request_id}/status`, { status: 'rejected' }, adm.token);
  assert.equal((await cancel(f.body.request_id)).status, 409);
  await s.call('PUT', `/admin/transport-requests/${f.body.request_id}/status`, { status: 'confirmed' }, adm.token);
  assert.equal((await cancel(f.body.request_id)).status, 200);

  // hotel requests
  const db = s.sql();
  db.pragma('foreign_keys = OFF');
  const now = new Date().toISOString();
  db.prepare("INSERT INTO hotels (hotel_id, external_hotel_id, name, city_code, location_id, cached_at) VALUES ('htc', 'extc', 'โรงแรมยกเลิก', 'X', ?, ?)").run(locId, now);
  db.prepare("INSERT INTO hotel_offers (offer_id, search_id, hotel_id, check_in_date, check_out_date, cached_at) VALUES ('ofc', 'srchc', 'htc', '2026-12-01', '2026-12-02', ?)").run(now);
  db.prepare("INSERT INTO booking_requests (booking_request_id, user_id, offer_id, guest_name, status, requested_at) VALUES ('brc', ?, 'ofc', 'g', 'requested', ?)").run(me.id, now);
  db.close();
  const hotelCancel = (token = me.token) => s.call('POST', '/booking/requests/brc/cancel', {}, token);
  assert.equal((await hotelCancel(other.token)).status, 404);
  assert.equal((await hotelCancel()).status, 200);
  assert.equal((await hotelCancel()).status, 409);
  const mine = (await s.call('GET', '/booking/requests', undefined, me.token)).body.requests.find((r) => r.booking_request_id === 'brc');
  assert.equal(mine.status, 'cancelled');
  assert.equal((await s.call('GET', '/admin/booking-requests', undefined, adm.token)).body.requests.find((r) => r.booking_request_id === 'brc').status, 'cancelled');
  assert.equal((await s.call('PUT', '/admin/booking-requests/brc/status', { status: 'cancelled' }, adm.token)).status, 200);
});
