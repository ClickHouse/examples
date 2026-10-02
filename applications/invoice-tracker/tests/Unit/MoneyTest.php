<?php

namespace Tests\Unit;

use App\Domain\Money;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class MoneyTest extends TestCase
{
    public function test_decimal_arithmetic_is_exact(): void
    {
        self::assertSame(10, Money::cents('0.10'));
        self::assertSame(1230, Money::cents('12.3'));
        self::assertSame(39999, Money::total([
            ['quantity' => 3, 'unit_cents' => 12500], ['quantity' => 1, 'unit_cents' => 2499]]));
        self::assertSame(30, Money::total([['quantity' => 3, 'unit_cents' => Money::cents('0.10')]]));
        self::assertSame('$399.99', Money::format(39999));
    }

    public function test_maximum_total_fits_signed_bigint(): void
    {
        self::assertSame(10_000_000_000_000, Money::total(array_fill(0, 100,
            ['quantity' => 1000, 'unit_cents' => 100_000_000])));
        self::assertSame(100_000_000, Money::cents('1000000.00'));
    }

    public static function malformedAmounts(): array
    {
        return array_map(fn ($value) => [$value], ['0.001', '1e2', '-1.00', 'NaN', '01.00', '1000000.01']);
    }

    #[DataProvider('malformedAmounts')]
    public function test_rejects_ambiguous_or_out_of_bounds_amount(string $value): void
    {
        $this->expectException(\InvalidArgumentException::class);
        Money::cents($value);
    }

    public function test_rejects_unsafe_quantity(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        Money::total([['quantity' => 1001, 'unit_cents' => 100_000_000]]);
    }
}
