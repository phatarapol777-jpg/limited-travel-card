const db = require('../db');
const { newId } = require('../util');
const { notify } = require('./notify');
const settings = require('./settings');
const { bangkokMonth, monthLabel, authorViews } = require('./communityService');

const BADGE_ICONS = { 1: 'gold', 2: 'silver', 3: 'bronze' };
const badgeTitle = (rank, ym) => `${rank === 1 ? 'แชมป์' : `อันดับ ${rank}`}นักเที่ยวประจำเดือน ${monthLabel(ym)}`;

/** Is the user's tag believable: a successful check-in at the place, or a claimed place card for it? */
function makeVerifier() {
  const checkin = db.prepare("SELECT 1 FROM travel_history WHERE user_id = ? AND location_id = ? AND status = 'success' LIMIT 1");
  const card = db.prepare(`SELECT 1 FROM all_cards c JOIN card_templates t ON t.template_id = c.template_id
    WHERE c.owner_user_id = ? AND t.location_id = ? AND c.activation_status IN ('CLAIMED', 'LOCKED_IN_TRADE') AND c.card_type = 'QUEST_LOCATION' LIMIT 1`);
  const cache = new Map();
  return (userId, locationId) => {
    const key = `${userId}|${locationId}`;
    if (!cache.has(key)) cache.set(key, !!(checkin.get(userId, locationId) || card.get(userId, locationId)));
    return cache.get(key);
  };
}

/**
 * Ranking for one Thailand-time month: how many different places each person tagged in visible posts. Ties go to whoever
 * reached their count first, then to the smaller user id, so the result never depends on row order.
 */
function computeMonth(ym) {
  const verify = settings.get('community_tag_verify') ? makeVerifier() : null;
  const rows = db.prepare(`SELECT p.user_id, p.location_id, p.timestamp FROM community_posts p JOIN users u ON u.user_id = p.user_id
    WHERE p.status = 'visible' AND p.location_id IS NOT NULL AND u.is_admin = 0 AND u.username NOT LIKE 'deleted-%'
      AND strftime('%Y-%m', datetime(p.timestamp, '+7 hours')) = ? ORDER BY p.timestamp, p.post_id`).all(ym);
  const perUser = new Map();
  for (const r of rows) {
    if (verify && !verify(r.user_id, r.location_id)) continue;
    const places = perUser.get(r.user_id) || new Map();
    if (!places.has(r.location_id)) places.set(r.location_id, r.timestamp); // first time this place was tagged
    perUser.set(r.user_id, places);
  }
  const ranked = [...perUser.entries()].map(([userId, places]) => {
    const times = [...places.values()].sort();
    return { user_id: userId, unique_count: places.size, reached_at: times[times.length - 1] };
  });
  ranked.sort((a, b) => b.unique_count - a.unique_count || (a.reached_at < b.reached_at ? -1 : a.reached_at > b.reached_at ? 1 : 0) || (a.user_id < b.user_id ? -1 : 1));
  return ranked.map((r, i) => ({ ...r, rank: i + 1 }));
}

/**
 * Closes every finished month that has not been closed yet: stores the final ranking and gives badges to the top N.
 * Called whenever someone asks for the leaderboard and from the maintenance job, so it does not matter when the server slept.
 * A month is closed once only (community_months is the guard), and badges are unique per person per month.
 */
function finalizePastMonths(now = Date.now()) {
  const current = bangkokMonth(now);
  const first = db.prepare("SELECT MIN(strftime('%Y-%m', datetime(timestamp, '+7 hours'))) AS m FROM community_posts WHERE location_id IS NOT NULL").get().m;
  if (!first || first >= current) return [];
  const done = new Set(db.prepare('SELECT year_month FROM community_months').all().map((r) => r.year_month));
  const finished = [];
  let [y, m] = first.split('-').map(Number);
  for (;;) {
    const ym = `${y}-${String(m).padStart(2, '0')}`;
    if (ym >= current) break;
    if (!done.has(ym)) {
      db.transaction(() => {
        if (db.prepare('SELECT 1 FROM community_months WHERE year_month = ?').get(ym)) return;
        const ranking = computeMonth(ym);
        const topN = settings.get('community_badge_top_n');
        const stamp = new Date(now).toISOString();
        db.prepare('INSERT INTO community_months (year_month, finalized_at) VALUES (?, ?)').run(ym, stamp);
        for (const r of ranking) {
          db.prepare('INSERT INTO checkin_monthly_stats (year_month, user_id, unique_count, rank_position) VALUES (?, ?, ?, ?)').run(ym, r.user_id, r.unique_count, r.rank);
          if (r.rank > topN) continue;
          const badgeId = newId('bdg');
          const added = db.prepare('INSERT OR IGNORE INTO user_badges (badge_id, user_id, awarded_month, rank_position, icon, title, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
            .run(badgeId, r.user_id, ym, r.rank, BADGE_ICONS[r.rank] || 'star', badgeTitle(r.rank, ym), stamp).changes;
          if (!added) continue;
          // the newest badge is worn by default; the user can change it (or hide it) from their profile
          db.prepare('UPDATE users SET selected_badge_id = ? WHERE user_id = ?').run(badgeId, r.user_id);
          notify(r.user_id, 'community_badge', `ยินดีด้วย! คุณได้อันดับ ${r.rank} นักเที่ยวประจำเดือน ${monthLabel(ym)} (เช็กอิน ${r.unique_count} สถานที่) และได้รับตราสัญลักษณ์พิเศษ`, { badge_id: badgeId, month: ym });
        }
        finished.push(ym);
      })();
    }
    m += 1;
    if (m > 12) { m = 1; y += 1; }
  }
  // this runs inside GET requests, which do not schedule a backup on their own: make sure the closed month is saved
  if (finished.length) require('./backup').markDirty();
  return finished;
}

/** The table for one month: live for the running month, the stored final result for a closed one. */
function leaderboard(ym, now = Date.now(), viewerId = null) {
  finalizePastMonths(now);
  const current = bangkokMonth(now);
  let rows;
  if (ym === current) {
    rows = computeMonth(ym).slice(0, 50).map((r) => ({ user_id: r.user_id, rank: r.rank, unique_count: r.unique_count }));
  } else {
    rows = db.prepare(`SELECT s.user_id, s.rank_position AS rank, s.unique_count FROM checkin_monthly_stats s JOIN users u ON u.user_id = s.user_id
      WHERE s.year_month = ? AND u.username NOT LIKE 'deleted-%' ORDER BY s.rank_position LIMIT 50`).all(ym);
  }
  const authors = authorViews(rows.map((r) => r.user_id), viewerId);
  return { month: ym, label: monthLabel(ym), finalized: ym !== current, rows: rows.map((r) => ({ rank: r.rank, unique_count: r.unique_count, author: authors.get(r.user_id), user_id: r.user_id })) };
}

/** Months that can be shown: the running one and every closed one, newest first. */
function availableMonths(now = Date.now()) {
  finalizePastMonths(now);
  const closed = db.prepare('SELECT year_month FROM community_months ORDER BY year_month DESC').all().map((r) => r.year_month);
  return [bangkokMonth(now), ...closed];
}

module.exports = { computeMonth, finalizePastMonths, leaderboard, availableMonths, badgeTitle };
