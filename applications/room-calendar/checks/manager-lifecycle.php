<?php

declare(strict_types=1);

require dirname(__DIR__).'/vendor/autoload.php';
$kernel = new App\Kernel('prod',false);
$kernel->boot();
$registry = $kernel->getContainer()->get('doctrine');
$workflow = new App\Workflow($registry);
$member = '00000000-0000-4000-8000-000000000001';
$room = '00000000-0000-4000-8000-000000000101';
$first = $workflow->create($member,$room,'Manager lifecycle accepted',
    App\Dto\Interval::parse('2026-11-20T08:00:00Z','2026-11-20T09:00:00Z'));
$before = $registry->getManager()->getUnitOfWork();
try {
    $workflow->create($member,$room,'Manager lifecycle conflict',
        App\Dto\Interval::parse('2026-11-20T08:30:00Z','2026-11-20T09:30:00Z'));
    throw new RuntimeException('Expected exclusion conflict.');
} catch (App\ApiProblem $failure) {
    if ($failure->status !== 409) { throw $failure; }
}
$after = $registry->getManager()->getUnitOfWork();
if ($before === $after || !$registry->getManager()->isOpen()) {
    throw new RuntimeException('Failed manager was not replaced with a fresh open unit of work.');
}
$valid = $workflow->create($member,$room,'Same workflow recovered',
    App\Dto\Interval::parse('2026-11-20T09:00:00Z','2026-11-20T10:00:00Z'));
if ($valid['status'] !== 'active' || $valid['revision'] !== 1) { throw new RuntimeException('Recovery failed.'); }
echo "Same PHP process/workflow: committed reservation, real 23P01→409, fresh open UnitOfWork, valid adjacent create committed.\n";
echo json_encode(['firstId'=>$first['id'],'recoveredId'=>$valid['id']],JSON_THROW_ON_ERROR)."\n";
