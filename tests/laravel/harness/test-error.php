<?php
// exercises: exception handling, 404/500 responses, error renderer

define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// 1. 404 - non-existent route
$request = Illuminate\Http\Request::create('/nonexistent', 'GET');
$request->headers->set('Accept', 'application/json');

$response = $kernel->handle($request);
echo "404_status: " . $response->getStatusCode() . "\n";

// 2. 500 - intentional error
$request = Illuminate\Http\Request::create('/error-test', 'GET');
$request->headers->set('Accept', 'application/json');

$response = $kernel->handle($request);
echo "500_status: " . $response->getStatusCode() . "\n";
$data = json_decode($response->getContent(), true);
echo "500_message: " . $data['message'] . "\n";
