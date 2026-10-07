<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
$rows = db()->query('SELECT * FROM snap_users ORDER BY created_at DESC')->fetchAll();
page_header('ผู้ใช้', 'users.php');
?>
<div class="panel"><table><thead><tr><th>Username</th><th>ชื่อ</th><th>อีเมล</th><th>การ์ด</th><th>เช็คอิน</th><th>สมัครเมื่อ</th></tr></thead><tbody>
<?php foreach ($rows as $r): ?>
  <tr><td><?= h($r['username']) ?></td><td><?= h($r['first_name'] . ' ' . $r['last_name']) ?></td><td><?= h($r['email']) ?></td>
      <td><?= (int)$r['cards'] ?></td><td><?= (int)$r['checkins'] ?></td><td><?= h(substr((string)$r['created_at'], 0, 16)) ?></td></tr>
<?php endforeach; ?>
<?php if (!$rows): ?><tr><td colspan="6" class="muted">ยังไม่มีข้อมูล</td></tr><?php endif; ?>
</tbody></table></div>
<?php page_footer();
