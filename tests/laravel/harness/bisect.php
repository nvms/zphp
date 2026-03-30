<?php
// bisection test to find where the x86_64 segfault occurs during Laravel bootstrap

echo "BISECT: starting\n";

echo "BISECT: defining LARAVEL_START\n";
define('LARAVEL_START', microtime(true));

echo "BISECT: requiring autoload\n";
require __DIR__ . '/../app/vendor/autoload.php';
echo "BISECT: autoload done\n";

echo "BISECT: requiring bootstrap/app.php\n";
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
echo "BISECT: bootstrap done, app class: " . get_class($app) . "\n";

echo "BISECT: making kernel\n";
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
echo "BISECT: kernel created, class: " . get_class($kernel) . "\n";

echo "BISECT: setting up SERVER vars\n";
$_SERVER['REQUEST_URI'] = '/';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['HTTP_HOST'] = 'localhost';

echo "BISECT: capturing request\n";
$request = Illuminate\Http\Request::capture();
echo "BISECT: request captured\n";

echo "BISECT: handling request\n";
$response = $kernel->handle($request);
echo "BISECT: response received, status: " . $response->getStatusCode() . "\n";
