<?php

// Development only: Linux workers enable competing HTTP acceptance requests.
$root = __DIR__.'/public';
$path = realpath($root.rawurldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH)));
if ($path && str_starts_with($path, $root.'/') && is_file($path)) {
    return false;
}
require $root.'/index.php';
