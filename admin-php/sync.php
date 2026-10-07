<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require_login();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: index.php');
    exit;
}
check_csrf();
try {
    $c = sync_all();
    flash('ok', sprintf('ซิงค์สำเร็จ: ผู้ใช้ %d, สถานที่ %d, เช็คอิน %d, คำขอจอง %d', $c['users'], $c['locations'], $c['checkins'], $c['bookings']));
} catch (Throwable $e) {
    flash('err', 'ซิงค์ไม่สำเร็จ: ' . $e->getMessage());
}
header('Location: ' . ($_SERVER['HTTP_REFERER'] ?? 'index.php'));
exit;
