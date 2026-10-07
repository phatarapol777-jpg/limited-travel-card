<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
$rows = db()->query('SELECT * FROM snap_checkins ORDER BY checked_at DESC')->fetchAll();
page_header('การเช็คอิน', 'checkins.php');
?>
<div class="panel"><table><thead><tr><th>เวลา</th><th>ผู้ใช้</th><th>สถานที่</th><th>จังหวัด</th><th>ยืนยันใบหน้า</th></tr></thead><tbody>
<?php foreach ($rows as $r): ?>
  <tr><td><?= h(substr((string)$r['checked_at'], 0, 16)) ?></td><td><?= h($r['username']) ?></td><td><?= h($r['location_name']) ?></td><td><?= h($r['province']) ?></td>
      <td><?php if ($r['photo_session_id']): ?><a class="btn small" href="photo.php?s=<?= h(urlencode((string)$r['photo_session_id'])) ?>">ดูภาพ</a><?php else: ?>-<?php endif; ?></td></tr>
<?php endforeach; ?>
<?php if (!$rows): ?><tr><td colspan="5" class="muted">ยังไม่มีข้อมูล</td></tr><?php endif; ?>
</tbody></table></div>
<?php page_footer();
