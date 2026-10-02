<?php

declare(strict_types=1);

namespace App\Dto;

use App\ApiProblem;

final readonly class Interval
{
    public function __construct(public \DateTimeImmutable $start, public \DateTimeImmutable $end) {}

    public static function instant(mixed $value): \DateTimeImmutable
    {
        if (!is_string($value) || !preg_match('/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})\z/D', $value)) {
            throw new ApiProblem(400, 'Use ISO8601 seconds with an explicit offset.');
        }
        $canonical = str_ends_with($value, 'Z') ? substr($value, 0, -1).'+00:00' : $value;
        $offset = substr($canonical, -6);
        if ((int) substr($offset, 1, 2) > 14 || (int) substr($offset, 4, 2) > 59
            || ((int) substr($offset, 1, 2) === 14 && substr($offset, 4, 2) !== '00')) {
            throw new ApiProblem(400, 'Offset must be between -14:00 and +14:00.');
        }
        $date = \DateTimeImmutable::createFromFormat('!Y-m-d\TH:i:sP', $canonical);
        $errors = \DateTimeImmutable::getLastErrors();
        if ($date === false || ($errors !== false && ($errors['warning_count'] || $errors['error_count']))
            || $date->format('Y-m-d\TH:i:sP') !== $canonical) {
            throw new ApiProblem(400, 'Invalid calendar instant.');
        }
        $utc = $date->setTimezone(new \DateTimeZone('UTC'));
        if ($utc < new \DateTimeImmutable('2000-01-01T00:00:00Z')
            || $utc >= new \DateTimeImmutable('2101-01-01T00:00:00Z')) {
            throw new ApiProblem(400, 'Instants must fall within UTC years 2000 through 2100.');
        }
        return $utc;
    }

    public static function parse(mixed $start, mixed $end, int $maximumSeconds = 43200): self
    {
        $first = self::instant($start);
        $last = self::instant($end);
        $duration = $last->getTimestamp() - $first->getTimestamp();
        if ($duration <= 0 || $duration > $maximumSeconds) {
            throw new ApiProblem(400, 'Interval must have positive bounded duration.');
        }
        return new self($first, $last);
    }
}
