<?php

declare(strict_types=1);

namespace App\Tests;

use App\ApiProblem;
use App\Dto\{Inputs,Interval};
use PHPUnit\Framework\TestCase;
use Symfony\Component\Validator\Validation;

final class InputsTest extends TestCase
{
    public function testOffsetsRepresentTheSameInstantAndAdjacency(): void
    {
        $first = Interval::parse('2026-10-02T09:00:00+01:00','2026-10-02T10:00:00+01:00');
        $second = Interval::parse('2026-10-02T08:00:00Z','2026-10-02T09:00:00Z');
        self::assertEquals($first->start,$second->start);
        self::assertSame('UTC',$first->start->getTimezone()->getName());
        self::assertSame(3600,$first->end->getTimestamp() - $first->start->getTimestamp());
    }

    public function testInvalidInstantsNeverNormalizeIntoAcceptedDates(): void
    {
        foreach ([null,'infinity','2026-10-02T08:00:00','2026-02-30T08:00:00Z',
                  '2026-10-02T24:00:00Z','2026-10-02T08:00:60Z','2026-10-02T08:00:00.1Z',
                  '2026-10-02T08:00:00+14:01','1999-12-31T23:59:59Z'] as $value) {
            try { Interval::instant($value); self::fail('Accepted invalid instant'); }
            catch (ApiProblem $failure) { self::assertSame(400,$failure->status); }
        }
        foreach (['2026-10-02T08:00:00Z','2026-10-02T07:59:59Z','2026-10-02T20:00:01Z'] as $end) {
            try { Interval::parse('2026-10-02T08:00:00Z',$end); self::fail('Accepted invalid interval'); }
            catch (ApiProblem $failure) { self::assertSame(400,$failure->status); }
        }
    }

    public function testNullAndForgedFieldsAreRejectedBeforeDatabaseUse(): void
    {
        $inputs = new Inputs(Validation::createValidator());
        foreach ([fn () => $inputs->uuid(null),fn () => $inputs->revision(null),
                  fn () => $inputs->revision('1'),fn () => $inputs->revision(1.5),
                  fn () => $inputs->title(null),fn () => $inputs->title("nul\0title"),
                  fn () => $inputs->fields(['roomId'=>'x','memberId'=>'forged'],['roomId'])] as $operation) {
            try { $operation(); self::fail('Invalid input accepted'); }
            catch (ApiProblem $failure) { self::assertSame(400,$failure->status); }
        }
        self::assertSame('abcdefab-cdef-4abc-8def-abcdefabcdef',$inputs->uuid('ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF'));
        self::assertSame(1000000000,$inputs->revision(1000000000));
    }
}
