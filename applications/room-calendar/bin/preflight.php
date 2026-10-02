<?php

declare(strict_types=1);

require dirname(__DIR__).'/vendor/autoload.php';
$kernel = new App\Kernel('prod', false);
$kernel->boot();
$registry = $kernel->getContainer()->get('doctrine');
if (count($registry->getManager()->getMetadataFactory()->getAllMetadata()) !== 1) {
    throw new RuntimeException('Expected one Reservation entity.');
}
$cases = [
    ['/reservations',['roomId'=>null,'title'=>'Synthetic','startAt'=>'2026-10-02T09:00:00Z','endAt'=>'2026-10-02T10:00:00Z']],
    ['/reservations/00000000-0000-4000-8000-000000000003/cancel',['expectedRevision'=>null]],
    ['/reservations',['roomId'=>'00000000-0000-4000-8000-000000000101','title'=>null,'startAt'=>'2026-10-02T09:00:00Z','endAt'=>'2026-10-02T10:00:00Z']],
];
foreach ($cases as [$path,$values]) {
    $request = Symfony\Component\HttpFoundation\Request::create($path,'POST',[],[],[],[
        'CONTENT_TYPE'=>'application/json','HTTP_AUTHORIZATION'=>'Bearer '.getenv('MEMBER_001_TOKEN'),
    ],json_encode($values,JSON_THROW_ON_ERROR));
    $response = $kernel->handle($request);
    if ($response->getStatusCode() !== 400) {
        throw new RuntimeException('Preflight expected 400; got '.$response->getStatusCode().' '.$response->getContent());
    }
    $kernel->terminate($request,$response);
}
echo "Native Doctrine metadata and actual Symfony JSON null boundaries passed without database connection.\n";
