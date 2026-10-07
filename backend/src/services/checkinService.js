const db = require('../db');
const { newId } = require('../util');
const { mintCard, getCard } = require('./cardService');

function awardCheckin(userId, locationId) {
  const location = db.prepare('SELECT * FROM locations WHERE location_id = ?').get(locationId);
  const now = new Date().toISOString();

  db.prepare('INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status) VALUES (?, ?, ?, ?, ?)')
    .run(newId('hist'), userId, locationId, now, 'success');

  const missions = db.prepare("SELECT * FROM missions WHERE location_id = ? AND status = 'active'").all(locationId);
  const awardedCards = [];
  const soldOutCards = [];
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
      const minted = mintCard({ templateId: template.template_id, userId, questCompletionId: mission.mission_id, reason: 'checkin' });
      if (minted.ok) awardedCards.push(getCard(minted.cardId));
      else soldOutCards.push({ name: template.name, reason: minted.reason });
    }
  }

  return { location, completed_missions: completedMissions, awarded_cards: awardedCards, sold_out_cards: soldOutCards };
}

module.exports = { awardCheckin };
