const crypto = require('crypto');
const db = require('./db');

const SESSION_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;

function newId(prefix) {
  return `${prefix}-${crypto.randomBytes(8).toString('hex')}`;
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return { hash, salt };
}

function verifyPassword(password, salt, expectedHash) {
  const { hash } = hashPassword(password, salt);
  return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(expectedHash));
}

function createSession(userId) {
  const token = crypto.randomBytes(24).toString('hex');
  db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)')
    .run(token, userId, new Date().toISOString());
  return token;
}

function authMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing token' });
  const session = db.prepare('SELECT * FROM sessions WHERE token = ?').get(token);
  if (!session) return res.status(401).json({ error: 'Invalid or expired token' });
  if (Date.now() - new Date(session.created_at).getTime() > SESSION_MAX_AGE_MS) {
    db.prepare('DELETE FROM sessions WHERE token = ?').run(token);
    return res.status(401).json({ error: 'Session expired, please sign in again' });
  }
  const user = db.prepare('SELECT * FROM users WHERE user_id = ?').get(session.user_id);
  if (!user) return res.status(401).json({ error: 'User not found' });
  req.user = user;
  req.token = token;
  next();
}

function adminMiddleware(req, res, next) {
  if (!req.user || !req.user.is_admin) return res.status(403).json({ error: 'Admin access required' });
  next();
}

function publicUser(user) {
  if (!user) return null;
  const { password_hash, password_salt, face_data, face_photo, face_descriptor, google_sub, ...rest } = user;
  return { ...rest, has_face: !!face_descriptor };
}

module.exports = { SESSION_MAX_AGE_MS, newId, hashPassword, verifyPassword, createSession, authMiddleware, adminMiddleware, publicUser };
