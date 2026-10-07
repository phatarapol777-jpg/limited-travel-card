const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');

const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(dataDir, { recursive: true });
const db = new Database(path.join(dataDir, 'app.db'));
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  user_id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  phone TEXT,
  face_data TEXT,
  is_admin INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS locations (
  location_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  province TEXT NOT NULL,
  icon TEXT,
  city_code TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS shops (
  shop_id TEXT PRIMARY KEY,
  shop_name TEXT NOT NULL,
  status TEXT NOT NULL,
  affiliate_link TEXT,
  contact_info TEXT,
  rating REAL,
  icon TEXT,
  location_id TEXT REFERENCES locations(location_id)
);

CREATE TABLE IF NOT EXISTS checkin_kiosks (
  kiosk_id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(location_id),
  mac_address TEXT UNIQUE NOT NULL,
  mock_ble_signal TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS missions (
  mission_id TEXT PRIMARY KEY,
  location_id TEXT NOT NULL REFERENCES locations(location_id),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  end_date TEXT,
  status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS card_templates (
  template_id TEXT PRIMARY KEY,
  location_id TEXT REFERENCES locations(location_id),
  mission_id TEXT REFERENCES missions(mission_id),
  name TEXT NOT NULL,
  icon TEXT NOT NULL,
  color_hex TEXT NOT NULL,
  type TEXT NOT NULL,
  rarity TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS all_cards (
  card_instance_id TEXT PRIMARY KEY,
  template_id TEXT NOT NULL REFERENCES card_templates(template_id),
  owner_user_id TEXT REFERENCES users(user_id),
  unique_code TEXT UNIQUE NOT NULL,
  acquired_at TEXT
);

CREATE TABLE IF NOT EXISTS travel_history (
  history_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  location_id TEXT NOT NULL REFERENCES locations(location_id),
  timestamp TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_missions (
  user_id TEXT NOT NULL REFERENCES users(user_id),
  mission_id TEXT NOT NULL REFERENCES missions(mission_id),
  completed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mission_id)
);

CREATE TABLE IF NOT EXISTS orders (
  order_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  card_instance_id TEXT NOT NULL UNIQUE REFERENCES all_cards(card_instance_id),
  shipping_address TEXT NOT NULL,
  tracking_number TEXT,
  status TEXT NOT NULL,
  ordered_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS community_posts (
  post_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  content TEXT,
  image_emoji TEXT,
  status TEXT NOT NULL,
  timestamp TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS community_likes (
  post_id TEXT NOT NULL REFERENCES community_posts(post_id),
  user_id TEXT NOT NULL REFERENCES users(user_id),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS community_comments (
  comment_id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES community_posts(post_id),
  user_id TEXT NOT NULL REFERENCES users(user_id),
  content TEXT NOT NULL,
  timestamp TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hotels (
  hotel_id TEXT PRIMARY KEY,
  external_hotel_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  city_code TEXT NOT NULL,
  location_id TEXT REFERENCES locations(location_id),
  latitude REAL,
  longitude REAL,
  cached_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hotel_searches (
  search_id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(user_id),
  location_id TEXT REFERENCES locations(location_id),
  city_code TEXT NOT NULL,
  check_in_date TEXT NOT NULL,
  check_out_date TEXT NOT NULL,
  adults INTEGER NOT NULL,
  searched_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hotel_offers (
  offer_id TEXT PRIMARY KEY,
  search_id TEXT NOT NULL REFERENCES hotel_searches(search_id),
  hotel_id TEXT NOT NULL REFERENCES hotels(hotel_id),
  external_offer_id TEXT,
  room_description TEXT,
  price_amount REAL,
  price_currency TEXT,
  check_in_date TEXT NOT NULL,
  check_out_date TEXT NOT NULL,
  raw_json TEXT,
  cached_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS booking_requests (
  booking_request_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  offer_id TEXT NOT NULL REFERENCES hotel_offers(offer_id),
  guest_name TEXT NOT NULL,
  status TEXT NOT NULL,
  requested_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS checkin_sessions (
  session_id TEXT PRIMARY KEY,
  kiosk_id TEXT NOT NULL REFERENCES checkin_kiosks(kiosk_id),
  location_id TEXT NOT NULL REFERENCES locations(location_id),
  user_id TEXT REFERENCES users(user_id),
  status TEXT NOT NULL,
  face_photo TEXT,
  result_json TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
`);

const userColumns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
if (!userColumns.includes('google_sub')) {
  db.exec('ALTER TABLE users ADD COLUMN google_sub TEXT');
}
for (const col of ['face_photo', 'face_descriptor']) {
  if (!userColumns.includes(col)) db.exec(`ALTER TABLE users ADD COLUMN ${col} TEXT`);
}
db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub ON users(google_sub) WHERE google_sub IS NOT NULL');

function addColumns(table, columns) {
  const existing = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
  for (const [name, type] of Object.entries(columns)) {
    if (!existing.includes(name)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${name} ${type}`);
  }
}
addColumns('checkin_kiosks', { kiosk_code: 'TEXT', last_seen_at: 'TEXT', last_ip: 'TEXT', last_lat: 'REAL', last_lng: 'REAL' });
addColumns('checkin_sessions', { session_key: 'TEXT', env_ok: 'INTEGER', phone_ip: 'TEXT', phone_lat: 'REAL', phone_lng: 'REAL' });
db.exec(`
CREATE UNIQUE INDEX IF NOT EXISTS idx_kiosks_code ON checkin_kiosks(kiosk_code) WHERE kiosk_code IS NOT NULL;

-- The kiosk's rotating "BLE" tokens (kept briefly so the server can re-check the token inside a phone's QR).
CREATE TABLE IF NOT EXISTS kiosk_ble_tokens (
  kiosk_id TEXT NOT NULL REFERENCES checkin_kiosks(kiosk_id),
  token TEXT NOT NULL,
  issued_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_kiosk_ble_tokens ON kiosk_ble_tokens(kiosk_id, issued_at);

-- One row per kiosk check-in attempt (passed or not).
CREATE TABLE IF NOT EXISTS checkin_audit (
  log_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  kiosk_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  face_match_score REAL,
  passed INTEGER NOT NULL,
  edge_passed INTEGER,
  edge_ms INTEGER,
  reason TEXT,
  checks_json TEXT
);
`);

// Registration photos are no longer stored; wipe any saved by earlier versions.
db.exec('UPDATE users SET face_photo = NULL WHERE face_photo IS NOT NULL');

module.exports = db;
