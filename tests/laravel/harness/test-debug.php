<?php
echo "step1: autoload\n";
define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
echo "step2: bootstrap\n";
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
echo "step3: kernel\n";
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
echo "step4: request\n";
$request = Illuminate\Http\Request::create('/', 'GET');
echo "step5: handle\n";
$response = $kernel->handle($request);
echo "step6: status=" . $response->getStatusCode() . "\n";
