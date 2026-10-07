<?php
declare(strict_types=1);

// Stores the Travel Card API's database snapshots (the API runs on a host whose disk is wiped when it sleeps).
// The snapshot is AES-256-GCM encrypted by the API with a key this server never sees, so this file only keeps
// opaque bytes. Access needs the API's token: the first token seen is remembered and every later request must match.

$dir = __DIR__ . '/backup_data';
if (!is_dir($dir)) {
    mkdir($dir, 0700, true);
}
if (!is_file($dir . '/.htaccess')) {
    file_put_contents($dir . '/.htaccess', "Require all denied\nDeny from all\n");
}

$token = (string)($_SERVER['HTTP_X_BACKUP_TOKEN'] ?? '');
if (!preg_match('/^[a-f0-9]{64}$/', $token)) {
    http_response_code(403);
    exit('forbidden');
}

$tokenFile = $dir . '/token.txt';
$snapshot = $dir . '/snapshot.bin';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if (!is_file($tokenFile)) {
    if ($method !== 'POST') {
        http_response_code(404); // nothing stored yet; do not claim the token on a read
        exit('empty');
    }
    file_put_contents($tokenFile, $token, LOCK_EX);
} elseif (!hash_equals(trim((string)file_get_contents($tokenFile)), $token)) {
    http_response_code(403);
    exit('forbidden');
}

if ($method === 'GET') {
    if (!is_file($snapshot)) {
        http_response_code(404);
        exit('empty');
    }
    header('Content-Type: application/octet-stream');
    header('Content-Length: ' . filesize($snapshot));
    readfile($snapshot);
    exit;
}

if ($method === 'POST') {
    $body = file_get_contents('php://input');
    if ($body === false || strlen($body) < 40 || strlen($body) > 30 * 1024 * 1024 || substr($body, 0, 4) !== 'TCB1') {
        http_response_code(400);
        exit('bad snapshot');
    }
    $tmp = $snapshot . '.tmp';
    file_put_contents($tmp, $body, LOCK_EX);
    if (is_file($snapshot)) {
        copy($snapshot, $dir . '/snapshot.prev.bin'); // keep one older copy in case a bad snapshot ever lands
    }
    rename($tmp, $snapshot);
    echo 'ok';
    exit;
}

http_response_code(405);
echo 'method not allowed';
