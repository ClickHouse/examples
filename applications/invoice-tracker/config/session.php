<?php

return [
    'driver' => 'database', 'lifetime' => 120, 'expire_on_close' => false,
    'encrypt' => false, 'connection' => 'pgsql', 'table' => 'sessions',
    'lottery' => [2, 100], 'cookie' => 'invoice_tracker_session', 'path' => '/',
    'domain' => null, 'secure' => env('SESSION_SECURE_COOKIE', true),
    'http_only' => true, 'same_site' => 'lax', 'partitioned' => false,
];
