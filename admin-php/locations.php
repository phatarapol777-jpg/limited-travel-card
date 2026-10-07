<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();

$fields = ['name', 'province', 'description', 'latitude', 'longitude', 'icon', 'mission_title', 'mission_description', 'card_name', 'card_color_hex', 'card_icon', 'card_rarity'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $action = (string)($_POST['action'] ?? '');
    $id = (string)($_POST['id'] ?? '');
    try {
        if ($id !== '' && !preg_match('/^[A-Za-z0-9_-]{1,64}$/', $id)) {
            throw new RuntimeException('รหัสสถานที่ไม่ถูกต้อง');
        }
        if ($action === 'delete') {
            admin_api('DELETE', '/admin/locations/' . rawurlencode($id));
            flash('ok', 'ลบสถานที่แล้ว');
        } elseif ($action === 'save') {
            $payload = [];
            foreach ($fields as $f) {
                $payload[$f] = trim((string)($_POST[$f] ?? ''));
            }
            $payload['latitude'] = (float)$payload['latitude'];
            $payload['longitude'] = (float)$payload['longitude'];
            if (!in_array($payload['card_rarity'], ['normal', 'rare', 'special'], true)) {
                $payload['card_rarity'] = 'normal';
            }
            if ($id !== '') {
                admin_api('PUT', '/admin/locations/' . rawurlencode($id), $payload);
            } else {
                admin_api('POST', '/admin/locations', $payload);
            }
            flash('ok', 'บันทึกสถานที่แล้ว');
        }
        sync_all();
    } catch (Throwable $e) {
        flash('err', $e->getMessage());
    }
    header('Location: locations.php');
    exit;
}

$pdo = db();
$editId = (string)($_GET['edit'] ?? '');
$new = isset($_GET['new']);
$editing = null;
if ($editId !== '') {
    $stmt = $pdo->prepare('SELECT * FROM snap_locations WHERE location_id = ?');
    $stmt->execute([$editId]);
    $editing = $stmt->fetch() ?: null;
}
$rows = $pdo->query('SELECT * FROM snap_locations ORDER BY name')->fetchAll();
page_header('สถานที่', 'locations.php');

if ($new || $editing):
    $v = static fn(string $k, string $d = '') => $editing[$k] ?? $d;
?>
<div class="panel">
  <h3 style="margin-top:0"><?= $editing ? 'แก้ไขสถานที่' : 'เพิ่มสถานที่ใหม่' ?></h3>
  <form method="post">
    <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="save">
    <input type="hidden" name="id" value="<?= h($editing['location_id'] ?? '') ?>">
    <div class="grid">
      <div><label>ชื่อสถานที่</label><input name="name" required value="<?= h($v('name')) ?>"></div>
      <div><label>จังหวัด</label><input name="province" required value="<?= h($v('province')) ?>"></div>
      <div><label>คำอธิบาย</label><input name="description" value="<?= h($v('description')) ?>"></div>
      <div><label>ละติจูด</label><input name="latitude" type="number" step="any" required value="<?= h($v('latitude')) ?>"></div>
      <div><label>ลองจิจูด</label><input name="longitude" type="number" step="any" required value="<?= h($v('longitude')) ?>"></div>
      <div><label>ไอคอน</label><input name="icon" value="<?= h($v('icon', 'place')) ?>"></div>
      <div><label>ชื่อภารกิจ</label><input name="mission_title" required value="<?= h($v('mission_title')) ?>"></div>
      <div><label>คำอธิบายภารกิจ</label><input name="mission_description" value="<?= h($v('mission_description')) ?>"></div>
      <div><label>ชื่อการ์ด</label><input name="card_name" required value="<?= h($v('card_name')) ?>"></div>
      <div><label>สีการ์ด (hex)</label><input name="card_color_hex" value="<?= h($v('card_color_hex', '#4C6B8A')) ?>"></div>
      <div><label>ไอคอนการ์ด</label><input name="card_icon" value="<?= h($v('card_icon', 'style')) ?>"></div>
      <div><label>ความหายาก</label><select name="card_rarity">
        <?php foreach (['normal', 'rare', 'special'] as $r): ?><option<?= $v('card_rarity') === $r ? ' selected' : '' ?>><?= h($r) ?></option><?php endforeach; ?>
      </select></div>
    </div>
    <p><button class="btn">บันทึก</button> <a class="btn small" href="locations.php">ยกเลิก</a></p>
  </form>
</div>
<?php endif; ?>

<div class="panel">
  <p><a class="btn" href="locations.php?new=1">+ เพิ่มสถานที่</a></p>
  <table><thead><tr><th>สถานที่</th><th>จังหวัด</th><th>ภารกิจ</th><th>การ์ด</th><th></th></tr></thead><tbody>
  <?php foreach ($rows as $r): ?>
    <tr><td><?= h($r['name']) ?></td><td><?= h($r['province']) ?></td><td><?= h($r['mission_title']) ?></td>
        <td><?= h($r['card_name']) ?> (<?= h($r['card_rarity']) ?>)</td>
        <td class="row"><a class="btn small" href="locations.php?edit=<?= h(urlencode((string)$r['location_id'])) ?>">แก้ไข</a>
          <form method="post" style="margin:0" onsubmit="return confirm('ลบสถานที่นี้ใช่หรือไม่?')">
            <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="delete"><input type="hidden" name="id" value="<?= h($r['location_id']) ?>">
            <button class="btn small danger">ลบ</button></form></td></tr>
  <?php endforeach; ?>
  <?php if (!$rows): ?><tr><td colspan="5" class="muted">ยังไม่มีข้อมูล</td></tr><?php endif; ?>
  </tbody></table>
</div>
<?php page_footer();
