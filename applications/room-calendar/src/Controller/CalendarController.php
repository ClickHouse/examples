<?php

declare(strict_types=1);

namespace App\Controller;

use App\{ApiProblem,Workflow};
use App\Dto\{Inputs,Interval};
use App\Security\MemberIdentity;
use Doctrine\DBAL\Connection;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\{JsonResponse,Request};
use Symfony\Component\Routing\Attribute\Route;

final class CalendarController extends AbstractController
{
    public function __construct(private readonly Inputs $inputs, private readonly Workflow $workflow,
                                private readonly Connection $connection) {}

    private function body(Request $request): array
    {
        if ($request->getContentTypeFormat() !== 'json') {
            throw new ApiProblem(415, 'Use application/json.');
        }
        if ((int) $request->headers->get('Content-Length', '0') > 4096) {
            throw new ApiProblem(413, 'Request body is limited to 4 KiB.');
        }
        $stream = $request->getContent(true);
        $raw = stream_get_contents($stream, 4097);
        if ($raw === false || strlen($raw) > 4096) {
            throw new ApiProblem(413, 'Request body is limited to 4 KiB.');
        }
        try {
            $object = json_decode($raw, false, 8, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new ApiProblem(400, 'Invalid JSON object.');
        }
        if (!$object instanceof \stdClass) {
            throw new ApiProblem(400, 'A JSON object is required.');
        }
        return (array) $object;
    }

    private function member(): string
    {
        $user = $this->getUser();
        if (!$user instanceof MemberIdentity) {
            throw new ApiProblem(401, 'Member identity is required.');
        }
        return $user->id;
    }

    #[Route('/health', methods: ['GET'])]
    public function health(): JsonResponse { return $this->json(['status' => 'ok']); }

    #[Route('/rooms', methods: ['GET'])]
    public function rooms(): JsonResponse
    {
        return $this->json(['rooms' => $this->connection->fetchAllAssociative(
            'SELECT id,name FROM calendar.rooms ORDER BY id LIMIT 20')]);
    }

    #[Route('/reservations', methods: ['POST'])]
    public function create(Request $request): JsonResponse
    {
        $values = $this->body($request);
        $this->inputs->fields($values, ['roomId','title','startAt','endAt']);
        $created = $this->workflow->create($this->member(), $this->inputs->uuid($values['roomId']),
            $this->inputs->title($values['title']), Interval::parse($values['startAt'],$values['endAt']));
        return $this->json($created, 201, ['Location' => '/reservations/'.$created['id']]);
    }

    #[Route('/reservations/{id}/reschedule', methods: ['POST'])]
    public function reschedule(string $id, Request $request): JsonResponse
    {
        $values = $this->body($request);
        $this->inputs->fields($values, ['expectedRevision','startAt','endAt']);
        return $this->json($this->workflow->change($this->member(), $this->inputs->uuid($id),
            $this->inputs->revision($values['expectedRevision']),
            Interval::parse($values['startAt'],$values['endAt'])));
    }

    #[Route('/reservations/{id}/cancel', methods: ['POST'])]
    public function cancel(string $id, Request $request): JsonResponse
    {
        $values = $this->body($request);
        $this->inputs->fields($values, ['expectedRevision']);
        return $this->json($this->workflow->change($this->member(), $this->inputs->uuid($id),
            $this->inputs->revision($values['expectedRevision']), null));
    }

    #[Route('/reservations', methods: ['GET'])]
    public function list(Request $request): JsonResponse
    {
        $values = $request->query->all();
        $this->inputs->fields($values, ['roomId','from','to']);
        $room = $this->inputs->uuid($values['roomId']);
        $interval = Interval::parse($values['from'],$values['to'],2678400);
        $rows = $this->connection->fetchAllAssociative(
            "SELECT id,room_id,title,status,revision,
                    to_char(start_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS start_at,
                    to_char(end_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS end_at
               FROM calendar.reservations
              WHERE room_id=? AND status='active'
                AND tstzrange(start_at,end_at,'[)') && tstzrange(?::timestamptz,?::timestamptz,'[)')
              ORDER BY start_at,id LIMIT 101",
            [$room,$interval->start->format('c'),$interval->end->format('c')]);
        $output = array_map(static fn (array $row): array => [
            'id' => $row['id'], 'roomId' => $row['room_id'], 'title' => $row['title'],
            'startAt' => $row['start_at'], 'endAt' => $row['end_at'],
            'status' => $row['status'], 'revision' => (int) $row['revision'],
        ], array_slice($rows, 0, 100));
        return $this->json(['reservations' => $output,'hasMore' => count($rows) > 100]);
    }
}
