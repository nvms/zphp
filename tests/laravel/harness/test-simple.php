<?php
// exercises: service container, middleware pipeline, router dispatch, closure route

define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

$_SERVER['REQUEST_URI'] = '/';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['HTTP_HOST'] = 'localhost';

$response = $kernel->handle(Illuminate\Http\Request::capture());
echo "status: " . $response->getStatusCode() . "\n";
echo "content: " . $response->getContent() . "\n";
