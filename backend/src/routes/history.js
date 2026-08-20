const express = require('express');
const db = require('../db');
const { authMiddleware } = require('../util');

const router = express.Router();

router.get('/', authMiddleware, (req, res) => {
  const history = db.prepare(`SELECT h.*, l.name AS location_name, l.province
    FROM travel_history h JOIN locations l ON l.location_id = h.location_id
    WHERE h.user_id = ? ORDER BY h.timestamp DESC`).all(req.user.user_id);
  res.json({ history });
});

module.exports = router;
