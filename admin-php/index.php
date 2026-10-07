<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
$pdo = db();
$count = static fn(string $t): int => (int)$pdo->query("SELECT COUNT(*) FROM $t")->fetchColumn();
$top = $pdo->query("SELECT l.name, l.province, (SELECT COUNT(*) FROM snap_checkins c WHERE c.location_name = l.name) AS n
                    FROM snap_locations l ORDER BY n DESC, l.name LIMIT 5")->fetchAll();
$last = $pdo->query('SELECT synced_at FROM sync_log ORDER BY synced_at DESC LIMIT 1')->fetchColumn();

page_header('ภาพรวม', 'index.php');
?>
<div class="stats">
  <div class="stat"><b><?= $count('snap_users') ?></b><span>ผู้ใช้</span></div>
  <div class="stat"><b><?= $count('snap_locations') ?></b><span>สถานที่</span></div>
  <div class="stat"><b><?= $count('snap_checkins') ?></b><span>เช็คอินสำเร็จ</span></div>
  <div class="stat"><b><?= $count('snap_bookings') ?></b><span>คำขอจอง</span></div>
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
