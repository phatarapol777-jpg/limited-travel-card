<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    try {
        [$status, $data] = api('POST', '/auth/login', [
            'username' => (string)($_POST['username'] ?? ''),
            'password' => (string)($_POST['password'] ?? ''),
        ]);
        if ($status !== 200) {
            $error = $data['error'] ?? 'เข้าสู่ระบบไม่สำเร็จ';
        } elseif ((int)($data['user']['is_admin'] ?? 0) !== 1) {
            $error = 'บัญชีนี้ไม่ใช่แอดมิน';
        } else {
            session_regenerate_id(true);
            $_SESSION['token'] = $data['token'];
            $_SESSION['admin_name'] = $data['user']['username'];
            try {
                sync_all();
            } catch (Throwable $e) {
                flash('err', 'เข้าสู่ระบบแล้ว แต่ซิงค์ข้อมูลไม่สำเร็จ: ' . $e->getMessage());
            }
            header('Location: index.php');
            exit;
        }
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}

page_header('เข้าสู่ระบบ');
?>
<div class="panel" style="max-width:360px;margin:60px auto">
  <h2 style="margin-top:0;color:var(--navy)">เข้าสู่ระบบแอดมิน</h2>
  <form method="post" autocomplete="off">
    <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">
    <label for="username">Username</label>
    <input id="username" name="username" required>
    <label for="password">Password</label>
    <input id="password" name="password" type="password" required>
    <?php if ($error !== ''): ?><p class="err"><?= h($error) ?></p><?php endif; ?>
    <p class="muted">ครั้งแรกหลัง API หลับอาจรอประมาณ 1 นาที</p>
    <button class="btn" style="width:100%">เข้าสู่ระบบ</button>
  </form>
</div>
<?php page_footer();
