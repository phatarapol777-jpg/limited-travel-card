<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
$pdo = db();
$count = static fn(string $t): int => (int)$pdo->query("SELECT COUNT(*) FROM $t")->fetchColumn();
$top = $pdo->query("SELECT l.name, l.province, (SELECT COUNT(*) FROM snap_checkins c WHERE c.location_name = l.name) AS n
                    FROM snap_locations l ORDER BY n DESC, l.name LIMIT 5")->fetchAll();
$last = $pdo->query('SELECT synced_at FROM sync_log ORDER BY synced_at DESC LIMIT 1')->fetchColumn();

// Read-only summary of the newer modules, straight from the traveler API. Review and moderation stay in the Node dashboard.
$modules = null;
$modulesError = null;
try {
    $modules = admin_api('GET', '/admin/stats', null, 8)['modules'] ?? null;
} catch (Throwable $e) {
    $modulesError = $e->getMessage();
}
$m = static fn(array $a, string $k): int => (int)($a[$k] ?? 0);

page_header('ภาพรวม', 'index.php');
?>
<div class="stats">
  <div class="stat"><b><?= $count('snap_users') ?></b><span>ผู้ใช้</span></div>
  <div class="stat"><b><?= $count('snap_locations') ?></b><span>สถานที่</span></div>
  <div class="stat"><b><?= $count('snap_checkins') ?></b><span>เช็คอินสำเร็จ</span></div>
  <div class="stat"><b><?= $count('snap_bookings') ?></b><span>คำขอจอง</span></div>
</div>
<div class="panel">
  <h3 style="margin-top:0">โมดูลใหม่ (ดูอย่างเดียว)</h3>
  <?php if ($modules === null): ?>
    <p class="muted">ยังโหลดข้อมูลโมดูลใหม่ไม่ได้<?= $modulesError ? ': ' . h($modulesError) : '' ?></p>
  <?php else: $q = $modules['quests'] ?? []; $s = $modules['merchants'] ?? []; $b = $modules['blind_packs'] ?? []; ?>
    <table><thead><tr><th>โมดูล</th><th>รออนุมัติ</th><th>เปิดใช้งาน</th><th>ไม่อนุมัติ</th><th>อื่น ๆ</th></tr></thead><tbody>
      <tr><td>ภารกิจจากผู้ใช้</td><td><?= $m($q, 'pending') ?></td><td><?= $m($q, 'approved') ?></td><td><?= $m($q, 'rejected') ?></td><td>ปิดแล้ว <?= $m($q, 'closed') ?></td></tr>
      <tr><td>ร้านค้าพันธมิตร</td><td><?= $m($s, 'pending') ?> (รอตรวจการแก้ไข <?= $m($s, 'revisions_waiting') ?>)</td><td><?= $m($s, 'approved') ?></td><td><?= $m($s, 'rejected') ?></td><td>ระงับ <?= $m($s, 'suspended') ?> · มีสิทธิประโยชน์ <?= $m($s, 'with_privileges') ?></td></tr>
      <tr><td>การ์ดสุ่ม (ของจริง)</td><td>-</td><td>แบบการ์ด <?= $m($b, 'designs') ?></td><td>-</td><td>ผู้สนใจสั่งซื้อ <?= $m($b, 'order_interest') ?></td></tr>
    </tbody></table>
    <p class="muted">การ์ดที่ถูกยกเลิกโดยผู้ดูแล: <?= $m($modules, 'cards_voided') ?> ใบ · การอนุมัติและจัดการอยู่ที่ Admin Dashboard (/admin/) ของระบบหลัก</p>
  <?php endif; ?>
</div>
<div class="panel">
  <h3 style="margin-top:0">สถานที่ที่มีคนเช็คอินมากที่สุด</h3>
  <table><thead><tr><th>สถานที่</th><th>จังหวัด</th><th>เช็คอิน</th></tr></thead><tbody>
  <?php foreach ($top as $r): ?>
    <tr><td><?= h($r['name']) ?></td><td><?= h($r['province']) ?></td><td><?= (int)$r['n'] ?></td></tr>
  <?php endforeach; ?>
  </tbody></table>
  <p class="muted">ข้อมูลจากฐานข้อมูล MySQL ของเว็บนี้ ซิงค์ล่าสุด: <?= h($last ?: 'ยังไม่เคยซิงค์') ?></p>
</div>
<?php page_footer();
