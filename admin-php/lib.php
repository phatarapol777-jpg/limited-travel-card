<?php
declare(strict_types=1);

session_start();

function config(): array {
    static $cfg = null;
    if ($cfg === null) {
        $file = __DIR__ . '/config.php';
        if (!is_file($file)) {
            http_response_code(500);
            exit('config.php not found. Copy config.sample.php to config.php and fill in the values.');
        }
        $cfg = require $file;
    }
    return $cfg;
}

function h($value): string {
    return htmlspecialchars((string)($value ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $cfg = config();
        $pdo = new PDO($cfg['db_dsn'], $cfg['db_user'] ?? null, $cfg['db_pass'] ?? null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        foreach (array_filter(array_map('trim', explode(';', (string)file_get_contents(__DIR__ . '/schema.sql')))) as $stmt) {
            $stmt = preg_replace('/^--.*$/m', '', $stmt);
            if (trim($stmt) !== '') {
                $pdo->exec($stmt);
            }
        }
    }
    return $pdo;
}

/** Calls the traveler app's REST API. Returns [httpStatus, decodedBody]. */
function api(string $method, string $path, ?array $body = null, ?string $token = null): array {
    if (!function_exists('curl_init')) {
        throw new RuntimeException('PHP cURL extension is not enabled on this server.');
    }
    $cfg = config();
    $headers = ['Content-Type: application/json', 'Accept: application/json'];
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }
    $ch = curl_init(rtrim($cfg['api_base'], '/') . $path);
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 90, // Render's free tier can take ~50s to wake up
        CURLOPT_CONNECTTIMEOUT => 20,
        CURLOPT_SSL_VERIFYPEER => $cfg['verify_ssl'] ?? true,
        CURLOPT_SSL_VERIFYHOST => ($cfg['verify_ssl'] ?? true) ? 2 : 0,
    ]);
    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE));
    }
    $raw = curl_exec($ch);
    if ($raw === false) {
        $err = curl_error($ch);
        curl_close($ch);
        throw new RuntimeException('เชื่อมต่อ API ไม่สำเร็จ: ' . $err);
    }
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    $decoded = json_decode((string)$raw, true);
    return [$status, is_array($decoded) ? $decoded : []];
}

/** API call using the logged-in admin's token; throws with the API's own message on failure. */
function admin_api(string $method, string $path, ?array $body = null): array {
    [$status, $data] = api($method, $path, $body, $_SESSION['token'] ?? null);
    if ($status === 401 || $status === 403) {
        session_destroy();
        header('Location: login.php');
        exit;
    }
    if ($status >= 400) {
        throw new RuntimeException($data['error'] ?? ('API error ' . $status));
    }
    return $data;
}

function require_login(): void {
    if (empty($_SESSION['token'])) {
        header('Location: login.php');
        exit;
    }
}

function csrf_token(): string {
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(16));
    }
    return $_SESSION['csrf'];
}

function check_csrf(): void {
    $sent = $_POST['csrf'] ?? '';
    if (!is_string($sent) || !hash_equals($_SESSION['csrf'] ?? '', $sent)) {
        http_response_code(400);
        exit('Invalid CSRF token');
    }
}

/** Replaces the MySQL snapshot with fresh data from the live API. */
function sync_all(): array {
    $pdo = db();
    $users = admin_api('GET', '/admin/users')['users'] ?? [];
    $locations = admin_api('GET', '/admin/locations')['locations'] ?? [];
    $checkins = admin_api('GET', '/admin/checkins')['checkins'] ?? [];
    $bookings = admin_api('GET', '/admin/booking-requests')['requests'] ?? [];

    $pdo->beginTransaction();
    try {
        foreach (['snap_users', 'snap_locations', 'snap_checkins', 'snap_bookings'] as $table) {
            $pdo->exec("DELETE FROM $table");
        }
        $ins = $pdo->prepare('REPLACE INTO snap_users (user_id, username, first_name, last_name, email, created_at, cards, checkins) VALUES (?,?,?,?,?,?,?,?)');
        foreach ($users as $u) {
            $ins->execute([$u['user_id'], $u['username'], $u['first_name'], $u['last_name'], $u['email'], $u['created_at'], (int)$u['cards'], (int)$u['checkins']]);
        }
        $ins = $pdo->prepare('REPLACE INTO snap_locations (location_id, name, province, description, latitude, longitude, icon, mission_title, mission_description, card_name, card_rarity, card_color_hex, card_icon) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)');
        foreach ($locations as $l) {
            $m = $l['mission'] ?? [];
            $c = $l['card'] ?? [];
            $ins->execute([$l['location_id'], $l['name'], $l['province'], $l['description'] ?? null, $l['latitude'], $l['longitude'], $l['icon'] ?? null,
                $m['title'] ?? null, $m['description'] ?? null, $c['name'] ?? null, $c['rarity'] ?? null, $c['color_hex'] ?? null, $c['icon'] ?? null]);
        }
        $ins = $pdo->prepare('REPLACE INTO snap_checkins (history_id, checked_at, username, location_name, province, photo_session_id) VALUES (?,?,?,?,?,?)');
        foreach ($checkins as $c) {
            $ins->execute([$c['history_id'], $c['timestamp'], $c['username'], $c['location_name'], $c['province'], $c['photo_session_id'] ?? null]);
        }
        $ins = $pdo->prepare('REPLACE INTO snap_bookings (booking_request_id, hotel_name, guest_name, username, check_in_date, check_out_date, price_amount, price_currency, status, requested_at) VALUES (?,?,?,?,?,?,?,?,?,?)');
        foreach ($bookings as $b) {
            $ins->execute([$b['booking_request_id'], $b['hotel_name'], $b['guest_name'], $b['username'], $b['check_in_date'], $b['check_out_date'], $b['price_amount'], $b['price_currency'], $b['status'], $b['requested_at']]);
        }
        $pdo->prepare('REPLACE INTO sync_log (synced_at, users_count, locations_count, checkins_count, bookings_count) VALUES (?,?,?,?,?)')
            ->execute([date('Y-m-d H:i:s'), count($users), count($locations), count($checkins), count($bookings)]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
    return ['users' => count($users), 'locations' => count($locations), 'checkins' => count($checkins), 'bookings' => count($bookings)];
}

function page_header(string $title, string $active = ''): void {
    $nav = ['index.php' => 'ภาพรวม', 'locations.php' => 'สถานที่', 'users.php' => 'ผู้ใช้', 'bookings.php' => 'คำขอจอง', 'checkins.php' => 'การเช็คอิน'];
    echo '<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">';
    echo '<title>' . h($title) . ' - Limited Travel Card Admin</title><style>
:root{--navy:#15294d;--bg:#f4f6fa;--line:#e3e7ef;--red:#c0392b;--green:#1e8e5a}*{box-sizing:border-box}
body{margin:0;font-family:system-ui,"Noto Sans Thai",sans-serif;background:var(--bg);color:#1b2433}
header{background:var(--navy);color:#fff;padding:14px 24px;display:flex;align-items:center;gap:16px}header h1{font-size:18px;margin:0;flex:1}
header a,header button{color:#fff;background:transparent;border:1px solid #ffffff55;padding:6px 12px;border-radius:6px;text-decoration:none;cursor:pointer;font:inherit}
main{max-width:1100px;margin:0 auto;padding:20px}nav.tabs{display:flex;gap:6px;margin:0 0 14px;flex-wrap:wrap}
nav.tabs a{background:#fff;border:1px solid var(--line);padding:8px 14px;border-radius:20px;color:inherit;text-decoration:none}
nav.tabs a.active{background:var(--navy);color:#fff;border-color:var(--navy)}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:16px}
.stat{background:#fff;border:1px solid var(--line);border-radius:10px;padding:16px}.stat b{display:block;font-size:28px;color:var(--navy)}.stat span{font-size:12px;color:#6b7690}
.panel{background:#fff;border:1px solid var(--line);border-radius:10px;padding:16px;overflow-x:auto;margin-bottom:16px}
table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;padding:9px 8px;border-bottom:1px solid var(--line);vertical-align:top}th{color:#6b7690;font-size:12px}
label{display:block;font-size:13px;color:#55607a;margin:10px 0 4px}input,select,textarea{width:100%;padding:9px 10px;border:1px solid var(--line);border-radius:6px;font:inherit}
.btn{background:var(--navy);color:#fff;border:0;padding:9px 16px;border-radius:6px;cursor:pointer;font:inherit;text-decoration:none;display:inline-block}
.btn.small{padding:5px 10px;background:#fff;color:inherit;border:1px solid var(--line)}.btn.danger{color:var(--red)}
.err{color:var(--red);margin:10px 0}.ok{color:var(--green);margin:10px 0}.muted{color:#6b7690;font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:0 14px}.row{display:flex;gap:6px;align-items:center}
</style></head><body><header><h1>Limited Travel Card · Admin</h1>';
    if (!empty($_SESSION['token'])) {
        echo '<form method="post" action="sync.php" style="margin:0"><input type="hidden" name="csrf" value="' . h(csrf_token()) . '"><button>ซิงค์ข้อมูลจาก API</button></form>';
        echo '<a href="logout.php">ออกจากระบบ</a>';
    }
    echo '</header><main>';
    if (!empty($_SESSION['token'])) {
        echo '<nav class="tabs">';
        foreach ($nav as $file => $label) {
            echo '<a href="' . h($file) . '"' . ($file === $active ? ' class="active"' : '') . '>' . h($label) . '</a>';
        }
        echo '</nav>';
    }
    if (!empty($_SESSION['flash'])) {
        echo '<p class="' . h($_SESSION['flash'][0]) . '">' . h($_SESSION['flash'][1]) . '</p>';
        unset($_SESSION['flash']);
    }
}

function page_footer(): void {
    echo '</main></body></html>';
}

function flash(string $type, string $message): void {
    $_SESSION['flash'] = [$type, $message];
}
