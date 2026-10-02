<?php

return [
    'default' => 'pgsql',
    'connections' => ['pgsql' => [
        'driver' => 'pgsql', 'host' => env('DB_HOST'), 'port' => env('DB_PORT', 5432),
        'database' => env('DB_DATABASE', 'postgres'), 'username' => env('DB_USERNAME'),
        'password' => env('DB_PASSWORD'), 'charset' => 'utf8', 'prefix' => '',
        'search_path' => 'invoice_tracker,public', 'sslmode' => 'verify-full',
        'sslrootcert' => env('DB_SSLROOTCERT'), 'connect_timeout' => 10,
    ]],
    'migrations' => ['table' => 'migrations', 'update_date_on_publish' => true],
];
