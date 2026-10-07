<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
$labels = ['requested' => 'รอดำเนินการ', 'confirmed' => 'ยืนยันแล้ว', 'rejected' => 'ปฏิเสธ', 'cancelled' => 'ผู้ใช้ยกเลิก'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $id = (string)($_POST['id'] ?? '');
    $status = (string)($_POST['status'] ?? '');
    if (isset($labels[$status]) && preg_match('/^[A-Za-z0-9_-]{1,64}$/', $id)) {
        try {
            admin_api('PUT', '/admin/booking-requests/' . rawurlencode($id) . '/status', ['status' => $status]);
            db()->prepare('UPDATE snap_bookings SET status = ? WHERE booking_request_id = ?')->execute([$status, $id]);
            flash('ok', 'อัปเดตสถานะแล้ว');
        } catch (Throwable $e) {
            flash('err', $e->getMessage());
        }
    }
    header('Location: bookings.php');
    exit;
}

$rows = db()->query('SELECT * FROM snap_bookings ORDER BY requested_at DESC')->fetchAll();
page_header('คำขอจอง', 'bookings.php');
?>
<div class="panel"><table><thead><tr><th>โรงแรม</th><th>ผู้เข้าพัก</th><th>ผู้ขอ</th><th>เข้าพัก</th><th>ราคา</th><th>สถานะ</th><th>เวลาขอ</th></tr></thead><tbody>
<?php foreach ($rows as $r): ?>
  <tr><td><?= h($r['hotel_name']) ?></td><td><?= h($r['guest_name']) ?></td><td><?= h($r['username']) ?></td>
      <td><?= h($r['check_in_date']) ?> → <?= h($r['check_out_date']) ?></td>
      <td><?= h(number_format((float)$r['price_amount'], 0)) ?> <?= h($r['price_currency']) ?></td>
      <td><form method="post" class="row" style="margin:0">
        <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="id" value="<?= h($r['booking_request_id']) ?>">
        <select name="status" onchange="this.form.submit()">
          <?php foreach ($labels as $v => $label): ?><option value="<?= h($v) ?>"<?= $r['status'] === $v ? ' selected' : '' ?>><?= h($label) ?></option><?php endforeach; ?>
        </select></form></td>
      <td><?= h(substr((string)$r['requested_at'], 0, 16)) ?></td></tr>
<?php endforeach; ?>
<?php if (!$rows): ?><tr><td colspan="7" class="muted">ยังไม่มีข้อมูล</td></tr><?php endif; ?>
</tbody></table></div>
<?php page_footer();
