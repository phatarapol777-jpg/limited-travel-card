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
addColumns('checkin_kiosks', { key_version: 'INTEGER NOT NULL DEFAULT 0', disabled: 'INTEGER NOT NULL DEFAULT 0' });
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

// ---- card system: serials, mint limits, activation status, ownership log, quests, trades ----------------------------
// Every change here is idempotent: a restored (older) snapshot is migrated again on each boot.
addColumns('card_templates', {
  card_type: 'TEXT', image: 'TEXT', lore: 'TEXT', mint_limit: 'INTEGER', minted_count: 'INTEGER NOT NULL DEFAULT 0', quest_id: 'TEXT',
});
addColumns('all_cards', {
  serial_number: 'INTEGER', activation_status: 'TEXT', card_type: 'TEXT', quest_completion_id: 'TEXT',
  physical_nfc_uid: 'TEXT', activation_code: 'TEXT', claimed_at: 'TEXT',
});
db.exec(`
CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_serial ON all_cards(template_id, serial_number) WHERE serial_number IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_activation ON all_cards(activation_code) WHERE activation_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cards_owner ON all_cards(owner_user_id);

-- Every change of hands (mint, activation, trade, gift), newest last.
CREATE TABLE IF NOT EXISTS card_ownership_log (
  log_id TEXT PRIMARY KEY,
  card_instance_id TEXT NOT NULL REFERENCES all_cards(card_instance_id),
  from_user_id TEXT,
  to_user_id TEXT,
  reason TEXT NOT NULL,
  trade_id TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ownership_card ON card_ownership_log(card_instance_id, created_at);
`);
db.transaction(() => {
  db.exec("UPDATE card_templates SET rarity = 'normal' WHERE rarity = 'common'");
  db.exec("UPDATE card_templates SET rarity = 'special' WHERE rarity = 'epic'");
  db.exec("UPDATE card_templates SET card_type = CASE WHEN type = 'random' THEN 'PHYSICAL_BLIND_PACK' ELSE 'QUEST_LOCATION' END WHERE card_type IS NULL");
  db.exec('UPDATE all_cards SET card_type = (SELECT card_type FROM card_templates t WHERE t.template_id = all_cards.template_id) WHERE card_type IS NULL');
  db.exec("UPDATE all_cards SET activation_status = CASE WHEN owner_user_id IS NULL THEN 'UNCLAIMED' ELSE 'CLAIMED' END WHERE activation_status IS NULL");
  db.exec('UPDATE all_cards SET claimed_at = acquired_at WHERE claimed_at IS NULL AND acquired_at IS NOT NULL');
  const maxSerial = db.prepare('SELECT COALESCE(MAX(serial_number), 0) AS m FROM all_cards WHERE template_id = ?');
  const setSerial = db.prepare('UPDATE all_cards SET serial_number = ? WHERE card_instance_id = ?');
  for (const row of db.prepare('SELECT card_instance_id, template_id FROM all_cards WHERE serial_number IS NULL ORDER BY template_id, acquired_at, rowid').all()) {
    setSerial.run(maxSerial.get(row.template_id).m + 1, row.card_instance_id);
  }
  db.exec('UPDATE card_templates SET minted_count = (SELECT COUNT(*) FROM all_cards WHERE all_cards.template_id = card_templates.template_id)');
})();

db.exec(`
-- Quests proposed by users (status: pending -> approved | rejected; approved ones can be closed). Each owns one reward card template.
CREATE TABLE IF NOT EXISTS quests (
  quest_id TEXT PRIMARY KEY,
  creator_user_id TEXT NOT NULL REFERENCES users(user_id),
  title TEXT NOT NULL,
  location_id TEXT NOT NULL REFERENCES locations(location_id),
  description TEXT NOT NULL,
  cover_image TEXT,
  start_date TEXT,
  end_date TEXT,
  permanent INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  reject_reason TEXT,
  template_id TEXT REFERENCES card_templates(template_id),
  created_at TEXT NOT NULL,
  reviewed_at TEXT,
  reviewed_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_quests_status ON quests(status, location_id);

-- One reward per user per quest.
CREATE TABLE IF NOT EXISTS quest_claims (
  quest_id TEXT NOT NULL REFERENCES quests(quest_id),
  user_id TEXT NOT NULL REFERENCES users(user_id),
  card_instance_id TEXT NOT NULL,
  claimed_at TEXT NOT NULL,
  PRIMARY KEY (quest_id, user_id)
);

-- In-app notifications (quest decisions, trade offers and results).
CREATE TABLE IF NOT EXISTS notifications (
  notification_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  type TEXT NOT NULL,
  text TEXT NOT NULL,
  data_json TEXT,
  read_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at);
`);

db.exec(`
-- "Order physical card" taps: measures demand before any card is printed. One row per user per card design.
CREATE TABLE IF NOT EXISTS physical_order_intents (
  intent_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  template_id TEXT NOT NULL REFERENCES card_templates(template_id),
  card_instance_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (user_id, template_id)
);
`);

db.exec(`
-- Card trades: a gift (offered card only) or a swap (offered card for a requested card). The offered card stays LOCKED_IN_TRADE while pending.
CREATE TABLE IF NOT EXISTS trades (
  trade_id TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users(user_id),
  to_user_id TEXT NOT NULL REFERENCES users(user_id),
  mode TEXT NOT NULL,
  offered_card_id TEXT NOT NULL REFERENCES all_cards(card_instance_id),
  requested_card_id TEXT REFERENCES all_cards(card_instance_id),
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  resolved_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_trades_to ON trades(to_user_id, status);
CREATE INDEX IF NOT EXISTS idx_trades_from ON trades(from_user_id, status);
`);

db.exec(`
-- The cards a user shows at the top of their profile (up to 5, in order).
CREATE TABLE IF NOT EXISTS user_pins (
  user_id TEXT NOT NULL REFERENCES users(user_id),
  card_instance_id TEXT NOT NULL REFERENCES all_cards(card_instance_id),
  position INTEGER NOT NULL,
  PRIMARY KEY (user_id, card_instance_id)
);
`);

db.exec(`
-- Admin-editable switches and numbers (see services/settings.js).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
`);

// Registration photos are no longer stored; wipe any saved by earlier versions.
db.exec('UPDATE users SET face_photo = NULL WHERE face_photo IS NOT NULL');

addColumns('physical_order_intents', { notified_at: 'TEXT' });

// ---- partner shops (merchants) and the perks they attach to cards ----------------------------------------------------------
db.exec(`
CREATE TABLE IF NOT EXISTS merchants (
  merchant_id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL REFERENCES users(user_id),
  shop_name_th TEXT NOT NULL,
  shop_name_en TEXT NOT NULL,
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  cover_image TEXT,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  address_detail TEXT NOT NULL,
  nearby_location_id TEXT REFERENCES locations(location_id),
  opening_hours TEXT NOT NULL,
  phone TEXT,
  facebook TEXT,
  instagram TEXT,
  line TEXT,
  approval_status TEXT NOT NULL,
  reject_reason TEXT,
  pending_revision TEXT,
  revision_note TEXT,
  legacy_shop_id TEXT UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  reviewed_at TEXT,
  reviewed_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_merchants_status ON merchants(approval_status);
CREATE INDEX IF NOT EXISTS idx_merchants_owner ON merchants(owner_user_id);

CREATE TABLE IF NOT EXISTS merchant_gallery (
  image_id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(merchant_id),
  position INTEGER NOT NULL,
  image TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_merchant_gallery ON merchant_gallery(merchant_id, position);

CREATE TABLE IF NOT EXISTS merchant_items (
  item_id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(merchant_id),
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  price REAL,
  image TEXT NOT NULL,
  is_signature INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_merchant_items ON merchant_items(merchant_id, position);

-- A perk a shop gives to holders of one card design; indexed by card so a card page can list the shops that honour it.
CREATE TABLE IF NOT EXISTS merchant_privileges (
  privilege_id TEXT PRIMARY KEY,
  merchant_id TEXT NOT NULL REFERENCES merchants(merchant_id),
  template_id TEXT NOT NULL REFERENCES card_templates(template_id),
  description TEXT NOT NULL,
  start_date TEXT,
  end_date TEXT
);
CREATE INDEX IF NOT EXISTS idx_privileges_template ON merchant_privileges(template_id);
CREATE INDEX IF NOT EXISTS idx_privileges_merchant ON merchant_privileges(merchant_id);
`);

// Flight and rental-car requests (the search results come live from the Booking.com wrapper, so the choice is stored as a snapshot).
db.exec(`
CREATE TABLE IF NOT EXISTS transport_requests (
  request_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  summary_json TEXT NOT NULL,
  price_amount REAL,
  price_currency TEXT,
  status TEXT NOT NULL,
  requested_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_transport_requests_user ON transport_requests(user_id, requested_at);
`);

// ---- community: public profiles, posts with pictures and place tags, reactions, follows, monthly leaderboard ------------------
addColumns('users', { display_name: 'TEXT', avatar: 'TEXT', cover: 'TEXT', bio: 'TEXT', selected_badge_id: 'TEXT', is_badge_visible: 'INTEGER NOT NULL DEFAULT 1', profile_rev: 'INTEGER NOT NULL DEFAULT 0' });
addColumns('community_posts', { updated_at: 'TEXT', location_id: 'TEXT' });
addColumns('community_comments', { image: 'TEXT', updated_at: 'TEXT' });

db.exec(`
CREATE TABLE IF NOT EXISTS post_images (
  image_id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES community_posts(post_id),
  position INTEGER NOT NULL,
  image TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_post_images ON post_images(post_id, position);

CREATE TABLE IF NOT EXISTS post_hashtags (
  post_id TEXT NOT NULL REFERENCES community_posts(post_id),
  tag TEXT NOT NULL,
  PRIMARY KEY (post_id, tag)
);
CREATE INDEX IF NOT EXISTS idx_post_hashtags_tag ON post_hashtags(tag);

CREATE TABLE IF NOT EXISTS post_reactions (
  post_id TEXT NOT NULL REFERENCES community_posts(post_id),
  user_id TEXT NOT NULL REFERENCES users(user_id),
  type TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_post_reactions_post ON post_reactions(post_id);

CREATE TABLE IF NOT EXISTS follows (
  follower_user_id TEXT NOT NULL REFERENCES users(user_id),
  following_user_id TEXT NOT NULL REFERENCES users(user_id),
  created_at TEXT NOT NULL,
  PRIMARY KEY (follower_user_id, following_user_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_user_id);

CREATE TABLE IF NOT EXISTS post_reports (
  post_id TEXT NOT NULL REFERENCES community_posts(post_id),
  reporter_user_id TEXT NOT NULL REFERENCES users(user_id),
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (post_id, reporter_user_id)
);

-- A month is finalised exactly once (lazily, the first time anyone asks after it ended); its ranking is then fixed.
CREATE TABLE IF NOT EXISTS community_months (
  year_month TEXT PRIMARY KEY,
  finalized_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS checkin_monthly_stats (
  year_month TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  unique_count INTEGER NOT NULL,
  rank_position INTEGER NOT NULL,
  PRIMARY KEY (year_month, user_id)
);
CREATE TABLE IF NOT EXISTS user_badges (
  badge_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  awarded_month TEXT NOT NULL,
  rank_position INTEGER NOT NULL,
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (user_id, awarded_month)
);
CREATE INDEX IF NOT EXISTS idx_community_posts_user ON community_posts(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_community_posts_time ON community_posts(status, timestamp);
CREATE INDEX IF NOT EXISTS idx_community_comments_post ON community_comments(post_id, timestamp);
`);

// Old "likes" become LIKE reactions, once (a later un-like must not bring them back on the next boot).
if (!db.prepare("SELECT 1 FROM settings WHERE key = 'migrated_likes_to_reactions'").get()) {
  db.transaction(() => {
    db.prepare("INSERT OR IGNORE INTO post_reactions (post_id, user_id, type, created_at) SELECT post_id, user_id, 'LIKE', ? FROM community_likes").run(new Date().toISOString());
    db.prepare("INSERT INTO settings (key, value, updated_at) VALUES ('migrated_likes_to_reactions', 'done', ?)").run(new Date().toISOString());
  })();
}

module.exports = db;
