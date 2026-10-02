<?php

declare(strict_types=1);

namespace App;

use App\Dto\Interval;
use App\Entity\Reservation;
use Doctrine\DBAL\LockMode;
use Doctrine\ORM\EntityManagerInterface;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

final readonly class Workflow
{
    public function __construct(private ManagerRegistry $registry) {}

    public static function response(Reservation $reservation): array
    {
        $utc = new \DateTimeZone('UTC');
        return [
            'id' => $reservation->id, 'roomId' => $reservation->roomId,
            'title' => $reservation->title,
            'startAt' => $reservation->startAt->setTimezone($utc)->format('Y-m-d\TH:i:s\Z'),
            'endAt' => $reservation->endAt->setTimezone($utc)->format('Y-m-d\TH:i:s\Z'),
            'status' => $reservation->status, 'revision' => $reservation->revision,
        ];
    }

    private function transaction(callable $operation): array
    {
        /** @var EntityManagerInterface $manager */
        $manager = $this->registry->getManager();
        try {
            // Doctrine flushes before committing, rolls back and closes on any failure.
            return $manager->wrapInTransaction($operation);
        } catch (\Throwable $failure) {
            // Discard all detached entities: their PHP fields may contain rolled-back values.
            if (!$manager->isOpen()) {
                $this->registry->resetManager();
            }
            for ($cause = $failure; $cause !== null; $cause = $cause->getPrevious()) {
                if (method_exists($cause, 'getSQLState') && $cause->getSQLState() === '23P01') {
                    throw new ApiProblem(409, 'This room already has an active reservation in that interval.');
                }
            }
            throw $failure;
        }
    }

    public function create(string $member, string $room, string $title, Interval $interval): array
    {
        return $this->transaction(function (EntityManagerInterface $manager) use ($member,$room,$title,$interval): array {
            if (!$manager->getConnection()->fetchOne('SELECT id FROM calendar.rooms WHERE id=?', [$room])) {
                throw new ApiProblem(404, 'Room not found.');
            }
            $reservation = new Reservation(Uuid::v4()->toRfc4122(), $room, $member, $title,
                                           $interval->start, $interval->end);
            $manager->persist($reservation);
            return self::response($reservation);
        });
    }

    public function change(string $member, string $id, int $expected, ?Interval $interval): array
    {
        return $this->transaction(function (EntityManagerInterface $manager) use ($member,$id,$expected,$interval): array {
            $reservation = $manager->createQueryBuilder()
                ->select('r')->from(Reservation::class, 'r')
                ->where('r.id = :id AND r.memberId = :member')
                ->setParameter('id', $id)->setParameter('member', $member)
                ->getQuery()->setLockMode(LockMode::PESSIMISTIC_WRITE)
                ->getOneOrNullResult();
            if ($reservation === null) {
                throw new ApiProblem(404, 'Owned reservation not found.');
            }
            if ($reservation->status === 'cancelled') {
                if ($interval === null && in_array($expected, [$reservation->revision,$reservation->revision - 1], true)) {
                    return self::response($reservation);
                }
                throw new ApiProblem(409, 'Reservation is cancelled or the revision is stale.');
            }
            if ($reservation->revision !== $expected || $expected >= 1000000000) {
                throw new ApiProblem(409, 'Reservation revision changed or is exhausted.');
            }
            if ($interval === null) {
                $reservation->status = 'cancelled';
            } else {
                $reservation->startAt = $interval->start;
                $reservation->endAt = $interval->end;
            }
            ++$reservation->revision;
            return self::response($reservation);
        });
    }
}
