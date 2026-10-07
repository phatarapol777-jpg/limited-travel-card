const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const express = require('express');
const cors = require('cors');
const backup = require('./services/backup');

async function main() {
  // On a host with a throw-away disk, bring back the last stored snapshot before the database file is opened.
  await backup.restoreIfMissing();

  const db = require('./db');
  require('./seed')();
  require('./services/kioskService').ensureKioskCodes();
  backup.start(db);
  const { expireTrades } = require('./services/tradeService');
  setInterval(() => { try { expireTrades(); } catch (e) { console.error('expireTrades', e.message); } }, 5 * 60 * 1000).unref();

  const app = express();
  // Behind Render's proxy, so req.ip is the real client address (used by the kiosk environment check).
  app.set('trust proxy', true);
  const allowedOrigins = (process.env.CORS_ORIGIN || '').split(',').map((s) => s.trim()).filter(Boolean);
  app.use(cors({ origin: allowedOrigins.length ? allowedOrigins : true }));
  app.use(express.json({ limit: '5mb' }));
  // Any write (except the kiosk's constant heartbeat) schedules a fresh backup snapshot.
  app.use((req, res, next) => {
    if (req.method !== 'GET' && req.method !== 'OPTIONS' && !req.path.endsWith('/heartbeat')) res.on('finish', backup.markDirty);
    next();
  });

  app.get('/api/health', (req, res) => res.json({ ok: true }));

  app.use('/api/auth', require('./routes/auth'));
  app.use('/api/catalog', require('./routes/catalog'));
  app.use('/api/cards', require('./routes/cards'));
  app.use('/api/community', require('./routes/community'));
  app.use('/api/history', require('./routes/history'));
  app.use('/api/booking', require('./routes/booking'));
  app.use('/api/kiosk', require('./routes/kiosk'));
  app.use('/api/quests', require('./routes/quests'));
  app.use('/api/media', require('./routes/media'));
  app.use('/api/trades', require('./routes/trades'));
  app.use('/api/users', require('./routes/users'));
  app.use('/api/notifications', require('./routes/notifications'));
  app.use('/api/admin', require('./routes/admin'));
  app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));

  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  });

  const PORT = process.env.PORT || 4000;
  app.listen(PORT, () => console.log(`Travel Card API listening on http://localhost:${PORT}`));

  // Render sends SIGTERM before it stops the instance: store a last snapshot first.
  process.on('SIGTERM', async () => {
    await backup.flush();
    process.exit(0);
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
