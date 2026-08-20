const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const express = require('express');
const cors = require('cors');
const seed = require('./seed');

seed();

const app = express();
const allowedOrigins = (process.env.CORS_ORIGIN || '').split(',').map((s) => s.trim()).filter(Boolean);
app.use(cors({ origin: allowedOrigins.length ? allowedOrigins : true }));
app.use(express.json({ limit: '5mb' }));

app.get('/api/health', (req, res) => res.json({ ok: true }));

app.use('/api/auth', require('./routes/auth'));
app.use('/api/catalog', require('./routes/catalog'));
app.use('/api/checkin', require('./routes/checkin'));
app.use('/api/cards', require('./routes/cards'));
app.use('/api/community', require('./routes/community'));
app.use('/api/history', require('./routes/history'));
app.use('/api/booking', require('./routes/booking'));
app.use('/api/kiosk', require('./routes/kiosk'));
app.use('/api/admin', require('./routes/admin'));

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Travel Card API listening on http://localhost:${PORT}`));
