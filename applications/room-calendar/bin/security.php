<?php

declare(strict_types=1);

require dirname(__DIR__).'/vendor/autoload.php';
$kernel = new App\Kernel('prod',false);
$kernel->boot();
$connection = $kernel->getContainer()->get('doctrine')->getConnection();
$expected = getenv('EXPECTED_TLS_FAILURE');
try {
    $control = $connection->fetchAssociative("SELECT current_user,version(),
        current_setting('statement_timeout') AS statement_timeout,
        current_setting('lock_timeout') AS lock_timeout,
        current_setting('TimeZone') AS timezone,
        (SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()) AS tls");
    if ($expected !== false) { throw new RuntimeException('Expected TLS failure unexpectedly connected.'); }
    echo json_encode($control,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n";
} catch (\Doctrine\DBAL\Exception $failure) {
    $message = $failure->getMessage();
    $verified = match ($expected) {
        'ca' => str_contains($message,'certificate verify failed'),
        'hostname' => str_contains($message,'does not match host name') || str_contains($message,'does not match hostname'),
        default => false,
    };
    if (!$verified) { throw new RuntimeException('Expected specific TLS error was not observed.',0,$failure); }
    echo 'Actual Symfony/DBAL/PDO libpq TLS '.$expected.' rejection confirmed; SQLState '.$failure->getSQLState()."\n";
}
