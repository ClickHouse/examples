<?php

namespace App\Domain;

use InvalidArgumentException;

final class Money
{
    public static function cents(string $value): int
    {
        // USD only: decimal input is parsed as text, never cast through float.
        if (! preg_match('/\A(0|[1-9][0-9]{0,6})(?:\.([0-9]{1,2}))?\z/D', $value, $parts)) {
            throw new InvalidArgumentException('Use USD amounts with at most two decimal places.');
        }
        $result = (int) $parts[1] * 100 + (int) str_pad($parts[2] ?? '', 2, '0');
        if ($result > 100_000_000) {
            throw new InvalidArgumentException('Unit price exceeds USD 1,000,000.00.');
        }

        return $result;
    }

    public static function format(int $cents): string
    {
        return '$'.number_format(intdiv($cents, 100), 0, '.', ',').'.'.str_pad((string) ($cents % 100), 2, '0', STR_PAD_LEFT);
    }

    public static function total(array $lines): int
    {
        $total = 0;
        if (count($lines) < 1 || count($lines) > 100) {
            throw new InvalidArgumentException('Use 1–100 lines.');
        }
        foreach ($lines as $line) {
            if (! is_int($line['quantity']) || $line['quantity'] < 1 || $line['quantity'] > 1000 ||
                ! is_int($line['unit_cents']) || $line['unit_cents'] < 0 || $line['unit_cents'] > 100_000_000) {
                throw new InvalidArgumentException('Invalid quantity or unit amount.');
            }
            $total += $line['quantity'] * $line['unit_cents'];
        }

        return $total; // Maximum 10^13 cents, safely within 64-bit PHP/Postgres bigint.
    }
}
