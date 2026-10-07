<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
$session = (string)($_GET['s'] ?? '');
$photo = null;
$error = '';
if (!preg_match('/^[A-Za-z0-9_-]{1,64}$/', $session)) {
    $error = 'รหัสไม่ถูกต้อง';
} else {
    try {
        $photo = admin_api('GET', '/admin/kiosk-sessions/' . rawurlencode($session) . '/photo')['photo'] ?? null;
        if (!is_string($photo) || !preg_match('#^data:image/jpeg;base64,[A-Za-z0-9+/=]+$#', $photo)) {
            $photo = null;
            $error = 'รูปแบบภาพไม่ถูกต้อง';
        }
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}
page_header('ภาพยืนยันตัวตน', 'checkins.php');
?>
<div class="panel">
  <?php if ($photo): ?><img src="<?= h($photo) ?>" alt="face capture" style="max-width:320px;border-radius:10px;border:1px solid var(--line)">
  <?php else: ?><p class="err"><?= h($error) ?></p><?php endif; ?>
  <p><a class="btn small" href="checkins.php">กลับ</a></p>
</div>
<?php page_footer();
