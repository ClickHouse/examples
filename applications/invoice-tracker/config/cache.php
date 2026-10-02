<?php

return ['default' => 'file', 'stores' => ['file' => ['driver' => 'file',
    'path' => storage_path('framework/cache/data'), 'lock_path' => storage_path('framework/cache/data')]],
    'prefix' => 'invoice_tracker'];
