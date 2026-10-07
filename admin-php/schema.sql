-- Limited Travel Card - admin snapshot tables (MySQL / also valid on SQLite for local tests).
-- Import via phpMyAdmin into database db273 (Import tab), or let the app create them on first login.

CREATE TABLE IF NOT EXISTS snap_users (
  user_id VARCHAR(64) PRIMARY KEY,
  username VARCHAR(100) NOT NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  email VARCHAR(190),
  created_at VARCHAR(40),
  cards INT NOT NULL DEFAULT 0,
  checkins INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS snap_locations (
  location_id VARCHAR(64) PRIMARY KEY,
  name VARCHAR(190) NOT NULL,
  province VARCHAR(100),
  description TEXT,
  latitude DOUBLE,
  longitude DOUBLE,
  icon VARCHAR(60),
  mission_title VARCHAR(190),
  mission_description TEXT,
  card_name VARCHAR(190),
  card_rarity VARCHAR(20),
  card_color_hex VARCHAR(20),
  card_icon VARCHAR(60)
);

CREATE TABLE IF NOT EXISTS snap_checkins (
  history_id VARCHAR(64) PRIMARY KEY,
  checked_at VARCHAR(40),
  username VARCHAR(100),
  location_name VARCHAR(190),
  province VARCHAR(100),
  photo_session_id VARCHAR(64)
);

CREATE TABLE IF NOT EXISTS snap_bookings (
  booking_request_id VARCHAR(64) PRIMARY KEY,
  hotel_name VARCHAR(255),
  guest_name VARCHAR(190),
  username VARCHAR(100),
  check_in_date VARCHAR(20),
  check_out_date VARCHAR(20),
  price_amount DOUBLE,
  price_currency VARCHAR(10),
  status VARCHAR(20),
  requested_at VARCHAR(40)
);

CREATE TABLE IF NOT EXISTS sync_log (
  synced_at VARCHAR(40) PRIMARY KEY,
  users_count INT,
  locations_count INT,
  checkins_count INT,
  bookings_count INT
);
