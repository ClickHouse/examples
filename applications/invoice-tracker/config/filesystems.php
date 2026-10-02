<?php

// No file-serving/upload routes are part of the invoice workflow.
return ['default' => 'local', 'disks' => ['local' => ['driver' => 'local',
    'root' => storage_path('app/private'), 'serve' => false, 'throw' => false]]];
