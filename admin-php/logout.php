<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

// End the API session too, so the token stops working everywhere (best effort: signing out here always succeeds).
if (!empty($_SESSION['token'])) {
    try {
        api('POST', '/auth/logout', [], $_SESSION['token']);
    } catch (Throwable $e) {
        // the API may be asleep or unreachable; the local session is cleared below regardless
    }
}
$_SESSION = [];
session_destroy();
header('Location: login.php');
exit;
