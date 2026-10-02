<?php

declare(strict_types=1);

namespace App;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Event\{ExceptionEvent,ResponseEvent};
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\KernelEvents;

final class Errors implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [KernelEvents::EXCEPTION => ['exception', 10],KernelEvents::RESPONSE => 'response'];
    }

    public function exception(ExceptionEvent $event): void
    {
        $error = $event->getThrowable();
        if ($error instanceof ApiProblem) {
            $response = new JsonResponse(['error' => $error->getMessage()], $error->status);
        } elseif ($error instanceof HttpExceptionInterface) {
            $response = new JsonResponse(['error' => 'Request could not be handled.'], $error->getStatusCode());
        } else {
            // Never expose SQL, driver messages, bearer tokens or connection fields.
            error_log('room-calendar failure class='.$error::class);
            $response = new JsonResponse(['error' => 'Service temporarily unavailable; reconcile an unconfirmed operation before retrying.'],503);
        }
        $event->setResponse($response);
    }

    public function response(ResponseEvent $event): void
    {
        $event->getResponse()->headers->set('Cache-Control','no-store');
        $event->getResponse()->headers->set('X-Content-Type-Options','nosniff');
    }
}
