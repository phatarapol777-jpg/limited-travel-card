<?php
// Copy this file to config.php on the server and fill in the real values.
// config.php must never be committed.
return [
    // Production MySQL on the university server (see the course sheet).
    'db_dsn'  => 'mysql:host=localhost;dbname=db273;charset=utf8mb4',
    'db_user' => 'usr273',
    'db_pass' => 'CHANGE_ME',

    // The traveler app's API (Node backend). Admin logs in with an account that has is_admin = 1.
    'api_base' => 'https://limited-travel-card-api.onrender.com/api',

    // Set to false only if the server's PHP/cURL has no CA bundle and HTTPS calls fail with an SSL error.
    'verify_ssl' => true,
];
