const db = require('../db');
const { newId } = require('../util');

/** Adds an in-app notification for a user. `data` is shown to the client as JSON (ids to open the related screen). */
function notify(userId, type, text, data = null) {
  db.prepare('INSERT INTO notifications (notification_id, user_id, type, text, data_json, read_at, created_at) VALUES (?, ?, ?, ?, ?, NULL, ?)')
    .run(newId('ntf'), userId, type, text, data ? JSON.stringify(data) : null, new Date().toISOString());
}

module.exports = { notify };
