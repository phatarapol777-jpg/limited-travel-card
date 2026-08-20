const express = require('express');
const db = require('../db');
const { newId, authMiddleware } = require('../util');

const router = express.Router();

router.get('/', authMiddleware, (req, res) => {
  const cards = db.prepare(`SELECT c.*, t.name, t.icon, t.color_hex, t.rarity, t.type,
      l.name AS location_name
    FROM all_cards c
    JOIN card_templates t ON t.template_id = c.template_id
    LEFT JOIN locations l ON l.location_id = t.location_id
    WHERE c.owner_user_id = ?
    ORDER BY c.acquired_at DESC`).all(req.user.user_id);
  res.json({ cards });
});

router.post('/transfer', authMiddleware, (req, res) => {
  const { card_instance_id, to_username } = req.body || {};
  const card = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(card_instance_id);
  if (!card) return res.status(404).json({ error: 'Card not found' });
  if (card.owner_user_id !== req.user.user_id) return res.status(403).json({ error: 'You do not own this card' });

  const target = db.prepare('SELECT * FROM users WHERE username = ?').get(to_username);
  if (!target) return res.status(404).json({ error: 'Recipient user not found' });
  if (target.user_id === req.user.user_id) return res.status(400).json({ error: 'Cannot transfer to yourself' });

  db.prepare('UPDATE all_cards SET owner_user_id = ? WHERE card_instance_id = ?').run(target.user_id, card_instance_id);
  res.json({ status: 'transferred', to: target.username });
});

router.post('/order', authMiddleware, (req, res) => {
  const { card_instance_id, shipping_address } = req.body || {};
  const card = db.prepare('SELECT * FROM all_cards WHERE card_instance_id = ?').get(card_instance_id);
  if (!card) return res.status(404).json({ error: 'Card not found' });
  if (card.owner_user_id !== req.user.user_id) return res.status(403).json({ error: 'You do not own this card' });
  if (!shipping_address) return res.status(400).json({ error: 'Shipping address required' });

  const existingOrder = db.prepare('SELECT 1 FROM orders WHERE card_instance_id = ?').get(card_instance_id);
  if (existingOrder) return res.status(409).json({ error: 'This card already has a pending order' });

  const orderId = newId('ord');
  db.prepare(`INSERT INTO orders (order_id, user_id, card_instance_id, shipping_address, tracking_number, status, ordered_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .run(orderId, req.user.user_id, card_instance_id, shipping_address, null, 'requested', new Date().toISOString());
  res.status(201).json({ order_id: orderId, status: 'requested' });
});

router.get('/orders', authMiddleware, (req, res) => {
  const orders = db.prepare(`SELECT o.*, t.name AS card_name FROM orders o
    JOIN all_cards c ON c.card_instance_id = o.card_instance_id
    JOIN card_templates t ON t.template_id = c.template_id
    WHERE o.user_id = ? ORDER BY o.ordered_at DESC`).all(req.user.user_id);
  res.json({ orders });
});

module.exports = router;
