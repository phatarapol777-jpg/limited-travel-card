const db = require('../db');
const { newId } = require('../util');

function awardCheckin(userId, locationId) {
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(locationId);
  const now = new Date().toISOString();

  db.prepare('INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status) VALUES (?, ?, ?, ?, ?)')
    .run(newId('hist'), userId, locationId, now, 'success');

  const missions = db.prepare("SELECT * FROM missions WHERE location_id = ? AND status = 'active'").all(locationId);
  const awardedCards = [];
  const completedMissions = [];

  for (const mission of missions) {
    const already = db.prepare('SELECT 1 FROM user_missions WHERE user_id = ? AND mission_id = ?')
      .get(userId, mission.mission_id);
    if (already) continue;

    db.prepare('INSERT INTO user_missions (user_id, mission_id, completed_at) VALUES (?, ?, ?)')
      .run(userId, mission.mission_id, now);
    completedMissions.push(mission);

    const template = db.prepare('SELECT * FROM card_templates WHERE mission_id = ?').get(mission.mission_id);
    if (template) {
      const cardId = newId('card');
      db.prepare(`INSERT INTO all_cards (card_instance_id, template_id, owner_user_id, unique_code, acquired_at)
        VALUES (?, ?, ?, ?, ?)`)
        .run(cardId, template.template_id, userId, newId('code'), now);
      awardedCards.push({ ...template, card_instance_id: cardId });
    }
  }

  return { location, completed_missions: completedMissions, awarded_cards: awardedCards };
}

module.exports = { awardCheckin };
