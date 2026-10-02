<?php

declare(strict_types=1);

namespace App\Entity;

use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'reservations', schema: 'calendar')]
class Reservation
{
    #[ORM\Id]
    #[ORM\Column(type: Types::GUID)]
    public string $id;

    #[ORM\Column(name: 'room_id', type: Types::GUID)]
    public string $roomId;

    #[ORM\Column(name: 'member_id', type: Types::GUID)]
    public string $memberId;

    #[ORM\Column(length: 120)]
    public string $title;

    #[ORM\Column(name: 'start_at', type: Types::DATETIMETZ_IMMUTABLE)]
    public \DateTimeImmutable $startAt;

    #[ORM\Column(name: 'end_at', type: Types::DATETIMETZ_IMMUTABLE)]
    public \DateTimeImmutable $endAt;

    #[ORM\Column(length: 9)]
    public string $status = 'active';

    #[ORM\Column]
    public int $revision = 1;

    public function __construct(string $id, string $roomId, string $memberId, string $title,
                                \DateTimeImmutable $start, \DateTimeImmutable $end)
    {
        $this->id = $id;
        $this->roomId = $roomId;
        $this->memberId = $memberId;
        $this->title = $title;
        $this->startAt = $start;
        $this->endAt = $end;
    }
}
