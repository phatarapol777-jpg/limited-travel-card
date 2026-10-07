const db = require('../db');
const { CARD_SELECT, cardView, RARITY_POINTS } = require('./cardService');

// The six regions of Thailand (77 provinces) used for "collected the whole northern zone" progress.
const REGIONS = {
  เหนือ: ['เชียงใหม่', 'เชียงราย', 'ลำปาง', 'ลำพูน', 'แม่ฮ่องสอน', 'น่าน', 'พะเยา', 'แพร่', 'อุตรดิตถ์'],
  ตะวันออกเฉียงเหนือ: ['กาฬสินธุ์', 'ขอนแก่น', 'ชัยภูมิ', 'นครพนม', 'นครราชสีมา', 'บึงกาฬ', 'บุรีรัมย์', 'มหาสารคาม', 'มุกดาหาร', 'ยโสธร', 'ร้อยเอ็ด', 'เลย', 'ศรีสะเกษ',
    'สกลนคร', 'สุรินทร์', 'หนองคาย', 'หนองบัวลำภู', 'อำนาจเจริญ', 'อุดรธานี', 'อุบลราชธานี'],
  กลาง: ['กรุงเทพมหานคร', 'กำแพงเพชร', 'ชัยนาท', 'นครนายก', 'นครปฐม', 'นครสวรรค์', 'นนทบุรี', 'ปทุมธานี', 'พระนครศรีอยุธยา', 'พิจิตร', 'พิษณุโลก', 'เพชรบูรณ์', 'ลพบุรี',
    'สมุทรปราการ', 'สมุทรสงคราม', 'สมุทรสาคร', 'สระบุรี', 'สิงห์บุรี', 'สุโขทัย', 'สุพรรณบุรี', 'อ่างทอง', 'อุทัยธานี'],
  ตะวันออก: ['จันทบุรี', 'ฉะเชิงเทรา', 'ชลบุรี', 'ตราด', 'ปราจีนบุรี', 'ระยอง', 'สระแก้ว'],
  ตะวันตก: ['กาญจนบุรี', 'ตาก', 'ประจวบคีรีขันธ์', 'เพชรบุรี', 'ราชบุรี'],
  ใต้: ['กระบี่', 'ชุมพร', 'ตรัง', 'นครศรีธรรมราช', 'นราธิวาส', 'ปัตตานี', 'พังงา', 'พัทลุง', 'ภูเก็ต', 'ยะลา', 'ระนอง', 'สงขลา', 'สตูล', 'สุราษฎร์ธานี'],
};
const REGION_OF = new Map(Object.entries(REGIONS).flatMap(([region, provinces]) => provinces.map((p) => [p, region])));
const REGION_LABEL = {
  เหนือ: 'ภาคเหนือ', ตะวันออกเฉียงเหนือ: 'ภาคตะวันออกเฉียงเหนือ', กลาง: 'ภาคกลาง', ตะวันออก: 'ภาคตะวันออก', ตะวันตก: 'ภาคตะวันตก', ใต้: 'ภาคใต้',
};

const RANKS = [
  { name: 'มือใหม่', min: 0 },
  { name: 'นักสะสม', min: 100 },
  { name: 'ชำนาญ', min: 300 },
  { name: 'ผู้เชี่ยวชาญ', min: 800 },
  { name: 'ตำนาน', min: 2000 },
];

function rankFor(points) {
  let index = 0;
  RANKS.forEach((r, i) => { if (points >= r.min) index = i; });
  const next = RANKS[index + 1] || null;
  return { name: RANKS[index].name, level: index + 1, min: RANKS[index].min, next_name: next ? next.name : null, next_min: next ? next.min : null };
}

/** Cards that currently count for a user: owned and activated (a card locked in a pending trade is still theirs). */
const OWNED = "c.owner_user_id = ? AND c.activation_status IN ('CLAIMED', 'LOCKED_IN_TRADE')";

function statsFor(userId) {
  const cards = db.prepare(`${CARD_SELECT} WHERE ${OWNED}`).all(userId);
  const points = cards.reduce((sum, c) => sum + (RARITY_POINTS[c.rarity] || 0), 0);
  const byRarity = { normal: 0, rare: 0, special: 0 };
  cards.forEach((c) => { if (byRarity[c.rarity] !== undefined) byRarity[c.rarity] += 1; });

  // "places conquered" comes from quest / location cards only (type 1)
  const placeCards = db.prepare(`SELECT DISTINCT t.location_id, l.province FROM all_cards c JOIN card_templates t ON t.template_id = c.template_id
    JOIN locations l ON l.location_id = t.location_id WHERE ${OWNED} AND c.card_type = 'QUEST_LOCATION'`).all(userId);
  const totalByRegion = {};
  for (const l of db.prepare('SELECT province FROM locations').all()) {
    const region = REGION_OF.get(l.province);
    if (region) totalByRegion[region] = (totalByRegion[region] || 0) + 1;
  }
  const collectedByRegion = {};
  for (const p of placeCards) {
    const region = REGION_OF.get(p.province);
    if (region) collectedByRegion[region] = (collectedByRegion[region] || 0) + 1;
  }
  const regions = Object.keys(totalByRegion).map((region) => ({
    region: REGION_LABEL[region],
    collected: collectedByRegion[region] || 0,
    total: totalByRegion[region],
    percent: Math.round(((collectedByRegion[region] || 0) / totalByRegion[region]) * 100),
  }));
  return {
    places_conquered: placeCards.length,
    total_cards: cards.length,
    by_rarity: byRarity,
    collector_points: points,
    rank: rankFor(points),
    regions,
  };
}

/** Pinned cards, in the order chosen, but only those the user still owns (a traded-away card drops out of the showcase). */
function pinsFor(userId) {
  const rows = db.prepare(`${CARD_SELECT} JOIN user_pins p ON p.card_instance_id = c.card_instance_id AND p.user_id = c.owner_user_id
    WHERE ${OWNED} AND p.user_id = ? ORDER BY p.position`).all(userId, userId);
  return rows.map(cardView);
}

module.exports = { REGIONS, REGION_OF, RANKS, rankFor, statsFor, pinsFor, OWNED };
