const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');

// The server secret behind kiosk keys and the encrypted database backup. Set KIOSK_SECRET in the environment so it
// survives a wiped disk; without it a random one is kept next to the database (and is lost with it).
function loadSecret() {
  if (process.env.KIOSK_SECRET) return process.env.KIOSK_SECRET;
  const file = path.join(dataDir, 'kiosk_secret');
  try {
    return fs.readFileSync(file, 'utf8').trim();
  } catch {
    const secret = crypto.randomBytes(24).toString('hex');
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(file, secret);
    return secret;
  }
}

const SECRET = loadSecret();

/** A purpose-specific subkey, so one leaked value never doubles as another. */
function derive(purpose) {
  return crypto.createHmac('sha256', SECRET).update(purpose).digest();
}

module.exports = { SECRET, derive, dataDir };
