const db = require('./db');
const { newId, hashPassword } = require('./util');

function seed() {
  const count = db.prepare('SELECT COUNT(*) AS c FROM locations').get().c;
  if (count > 0) return;

  const now = new Date().toISOString();

  const locations = [
    { name: 'วัดพระแก้ว', description: 'วัดพระศรีรัตนศาสดาราม สถานที่ศักดิ์สิทธิ์คู่บ้านคู่เมือง', lat: 13.7515, lng: 100.4924, province: 'กรุงเทพมหานคร', icon: 'temple_buddhist', cityCode: 'Bangkok' },
    { name: 'ดอยสุเทพ', description: 'วัดพระธาตุดอยสุเทพ วิวเมืองเชียงใหม่แบบพาโนรามา', lat: 18.8047, lng: 98.9217, province: 'เชียงใหม่', icon: 'landscape', cityCode: 'Chiang Mai' },
    { name: 'เกาะพีพี', description: 'เกาะสวรรค์แห่งอันดามัน น้ำทะเลใสสีเทอร์ควอยซ์', lat: 7.7407, lng: 98.7784, province: 'กระบี่', icon: 'beach_access', cityCode: 'Krabi' },
    { name: 'อุทยานประวัติศาสตร์สุโขทัย', description: 'มรดกโลกทางประวัติศาสตร์ ราชธานีแห่งแรกของไทย', lat: 17.0175, lng: 99.7089, province: 'สุโขทัย', icon: 'account_balance', cityCode: 'Sukhothai' },
    { name: 'สะพานข้ามแม่น้ำแคว', description: 'สะพานประวัติศาสตร์สมัยสงครามโลกครั้งที่ 2', lat: 14.0392, lng: 99.5079, province: 'กาญจนบุรี', icon: 'train', cityCode: 'Kanchanaburi' },
    { name: 'ภูทอก', description: 'ภูเขาหินทรายพร้อมสะพานไม้ไต่เขา 7 ชั้น', lat: 18.1244, lng: 103.6501, province: 'บึงกาฬ', icon: 'terrain', cityCode: 'Udon Thani' },
  ];

  const locationIds = [];
  const insertLoc = db.prepare(`INSERT INTO locations (location_id, name, description, latitude, longitude, province, icon, city_code, created_at)
    VALUES (@location_id, @name, @description, @latitude, @longitude, @province, @icon, @city_code, @created_at)`);
  for (const loc of locations) {
    const id = newId('loc');
    locationIds.push(id);
    insertLoc.run({
      location_id: id, name: loc.name, description: loc.description,
      latitude: loc.lat, longitude: loc.lng, province: loc.province,
      icon: loc.icon, city_code: loc.cityCode, created_at: now,
    });
  }

  const insertKiosk = db.prepare(`INSERT INTO checkin_kiosks (kiosk_id, location_id, mac_address, mock_ble_signal, status)
    VALUES (?, ?, ?, ?, ?)`);
  locationIds.forEach((locId, i) => {
    insertKiosk.run(newId('kiosk'), locId, `AA:BB:CC:00:00:${(10 + i).toString(16)}`, `BLE-BEACON-${i}`, 'online');
  });

  const shops = [
    { name: 'ร้านอาหารริมโขงภูทอก', rating: 4.6, icon: 'restaurant', locIdx: 5 },
    { name: 'คาเฟ่ดอยสุเทพวิว', rating: 4.8, icon: 'local_cafe', locIdx: 1 },
    { name: 'ร้านของฝากเกาะพีพี', rating: 4.4, icon: 'store', locIdx: 2 },
    { name: 'สตูดิโอผ้าไทยสุโขทัย', rating: 4.7, icon: 'checkroom', locIdx: 3 },
    { name: 'ร้านเช่าจักรยานกาญจนบุรี', rating: 4.5, icon: 'pedal_bike', locIdx: 4 },
  ];
  const insertShop = db.prepare(`INSERT INTO shops (shop_id, shop_name, status, affiliate_link, contact_info, rating, icon, location_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const s of shops) {
    insertShop.run(newId('shop'), s.name, 'active', 'https://example.com/partner', '08x-xxx-xxxx', s.rating, s.icon, locationIds[s.locIdx]);
  }

  const missionDefs = [
    { title: 'เยือนวัดพระแก้ว', desc: 'เช็คอินที่วัดพระแก้วเพื่อรับการ์ดที่ระลึก', locIdx: 0 },
    { title: 'พิชิตดอยสุเทพ', desc: 'เดินทางถึงวัดพระธาตุดอยสุเทพ', locIdx: 1 },
    { title: 'สำรวจเกาะพีพี', desc: 'เช็คอินที่เกาะพีพีเพื่อปลดล็อกการ์ดหายาก', locIdx: 2 },
    { title: 'ย้อนรอยสุโขทัย', desc: 'เที่ยวชมอุทยานประวัติศาสตร์สุโขทัย', locIdx: 3 },
    { title: 'ข้ามสะพานประวัติศาสตร์', desc: 'เช็คอินที่สะพานข้ามแม่น้ำแคว', locIdx: 4 },
    { title: 'ไต่บันไดภูทอก', desc: 'เช็คอินที่ภูทอก บึงกาฬ', locIdx: 5 },
  ];
  const missionIds = [];
  const insertMission = db.prepare(`INSERT INTO missions (mission_id, location_id, title, description, end_date, status)
    VALUES (?, ?, ?, ?, ?, ?)`);
  for (const m of missionDefs) {
    const id = newId('msn');
    missionIds.push(id);
    insertMission.run(id, locationIds[m.locIdx], m.title, m.desc, null, 'active');
  }

  const cardDefs = [
    { name: 'การ์ดวัดพระแก้ว', icon: 'temple_buddhist', color: '#C9A227', type: 'mission', rarity: 'rare', locIdx: 0, msnIdx: 0 },
    { name: 'การ์ดดอยสุเทพ', icon: 'landscape', color: '#4C6B8A', type: 'mission', rarity: 'common', locIdx: 1, msnIdx: 1 },
    { name: 'การ์ดเกาะพีพี', icon: 'beach_access', color: '#1CA9C9', type: 'mission', rarity: 'epic', locIdx: 2, msnIdx: 2 },
    { name: 'การ์ดสุโขทัย', icon: 'account_balance', color: '#8B5E3C', type: 'mission', rarity: 'rare', locIdx: 3, msnIdx: 3 },
    { name: 'การ์ดแม่น้ำแคว', icon: 'train', color: '#5A7D5A', type: 'mission', rarity: 'common', locIdx: 4, msnIdx: 4 },
    { name: 'การ์ดภูทอก', icon: 'terrain', color: '#7A4F9E', type: 'mission', rarity: 'epic', locIdx: 5, msnIdx: 5 },
    { name: 'การ์ดนักสะสมมือใหม่', icon: 'star', color: '#B0B0B0', type: 'random', rarity: 'common', locIdx: null, msnIdx: null },
    { name: 'การ์ดนักเดินทางตำนาน', icon: 'auto_awesome', color: '#D4AF37', type: 'random', rarity: 'epic', locIdx: null, msnIdx: null },
  ];
  const templateIds = [];
  const insertTemplate = db.prepare(`INSERT INTO card_templates (template_id, location_id, mission_id, name, icon, color_hex, type, rarity)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const c of cardDefs) {
    const id = newId('tpl');
    templateIds.push(id);
    insertTemplate.run(
      id,
      c.locIdx === null ? null : locationIds[c.locIdx],
      c.msnIdx === null ? null : missionIds[c.msnIdx],
      c.name, c.icon, c.color, c.type, c.rarity,
    );
  }

  // Demo user with a few community posts so the feed isn't empty on first run
  const demoUserId = newId('usr');
  const { hash, salt } = hashPassword('demo1234');
  db.prepare(`INSERT INTO users (user_id, username, password_hash, password_salt, first_name, last_name, email, phone, face_data, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(demoUserId, 'demo_traveler', hash, salt, 'สมชาย', 'นักเดินทาง', 'demo@travelcard.app', '080-000-0000', null, now);

  const insertAllCard = db.prepare(`INSERT INTO all_cards (card_instance_id, template_id, owner_user_id, unique_code, acquired_at)
    VALUES (?, ?, ?, ?, ?)`);
  [0, 1, 6].forEach((tplIdx) => {
    insertAllCard.run(newId('card'), templateIds[tplIdx], demoUserId, newId('code'), now);
  });

  const insertHistory = db.prepare(`INSERT INTO travel_history (history_id, user_id, location_id, timestamp, status)
    VALUES (?, ?, ?, ?, ?)`);
  insertHistory.run(newId('hist'), demoUserId, locationIds[0], now, 'success');
  insertHistory.run(newId('hist'), demoUserId, locationIds[1], now, 'success');

  db.prepare('INSERT INTO user_missions (user_id, mission_id, completed_at) VALUES (?, ?, ?)')
    .run(demoUserId, missionIds[0], now);
  db.prepare('INSERT INTO user_missions (user_id, mission_id, completed_at) VALUES (?, ?, ?)')
    .run(demoUserId, missionIds[1], now);

  const posts = [
    { content: 'เพิ่งเช็คอินที่วัดพระแก้วสำเร็จ! ได้การ์ดลิมิเต็ดใบแรกแล้ว ตื่นเต้นมาก 🎉', emoji: '🛕' },
    { content: 'วิวจากดอยสุเทพสวยมาก แนะนำให้ไปตอนเช้าเลยค่ะ อากาศเย็นสบาย', emoji: '⛰️' },
  ];
  const insertPost = db.prepare(`INSERT INTO community_posts (post_id, user_id, content, image_emoji, status, timestamp)
    VALUES (?, ?, ?, ?, ?, ?)`);
  const postIds = [];
  for (const p of posts) {
    const id = newId('post');
    postIds.push(id);
    insertPost.run(id, demoUserId, p.content, p.emoji, 'visible', now);
  }
  db.prepare('INSERT INTO community_comments (comment_id, post_id, user_id, content, timestamp) VALUES (?, ?, ?, ?, ?)')
    .run(newId('cmt'), postIds[0], demoUserId, 'ยินดีด้วยนะ! ใบไหนหายากสุด?', now);

  console.log('Seed data inserted.');
}

module.exports = seed;
