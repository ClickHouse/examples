<?php

use App\Domain\InvoiceLifecycle;
use Composer\InstalledVersions;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Application;
use Illuminate\Support\Facades\DB;

require __DIR__.'/../vendor/autoload.php';
$app = require __DIR__.'/../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();
$mode = $argv[1];
if ($mode === 'rollback') {
    try {
        (new InvoiceLifecycle)->edit((int) $argv[2], (int) $argv[3],
            ['recipient' => 'Must roll back', 'reference' => 'Must roll back'],
            [['description' => str_repeat('x', 201), 'quantity' => 1, 'unit_cents' => 10]]);
        throw new RuntimeException('Expected rejected line insert');
    } catch (QueryException $error) {
        if (($error->errorInfo[0] ?? '') !== '22001') {
            throw $error;
        }
        echo "Rejected oversize database line after draft update/delete; transaction rolled back.\n";
    }
} elseif ($mode === 'tls-ca' || $mode === 'tls-host') {
    if ($mode === 'tls-ca') {
        config(['database.connections.pgsql.sslrootcert' => '/etc/ssl/certs/ca-certificates.crt']);
    } else {
        putenv('PGHOSTADDR='.gethostbyname(config('database.connections.pgsql.host')));
        config(['database.connections.pgsql.host' => 'mismatch.invalid']);
    }
    DB::purge('pgsql');
    try {
        DB::select('SELECT 1');
        throw new RuntimeException('Invalid TLS configuration was accepted');
    } catch (QueryException|PDOException $error) {
        $message = $error->getMessage();
        $expected = $mode === 'tls-ca' ? str_contains($message, 'certificate verify failed')
            : (str_contains($message, 'does not match host name') || str_contains($message, 'hostname mismatch'));
        if (! $expected) {
            throw new RuntimeException('TLS control failed for an unrelated reason');
        }
        echo "$mode: certificate-specific rejection through Laravel PDO connection passed.\n";
    }
} else {
    $ssl = DB::selectOne('SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()')->ssl;
    if (! $ssl) {
        throw new RuntimeException('TLS inactive');
    }
    echo json_encode(['php' => PHP_VERSION, 'laravel' => Application::VERSION,
        'pint' => InstalledVersions::getPrettyVersion('laravel/pint'),
        'phpunit' => InstalledVersions::getPrettyVersion('phpunit/phpunit'),
        'pdo_pgsql' => phpversion('pdo_pgsql'), 'libpq' => DB::connection()->getPdo()->getAttribute(PDO::ATTR_CLIENT_VERSION),
        'postgres' => DB::selectOne('SHOW server_version')->server_version, 'verified_tls' => true])."\n";
}
