<?php
// bisection test to find where the x86_64 segfault occurs during Laravel bootstrap
// uses file_put_contents to php://stderr for unbuffered output (survives crash)

function bisect_log($msg) {
    file_put_contents('php://stderr', "BISECT: $msg\n");
}

bisect_log("starting");

bisect_log("defining LARAVEL_START");
define('LARAVEL_START', microtime(true));

bisect_log("requiring autoload");
require __DIR__ . '/../app/vendor/autoload.php';
bisect_log("autoload done");

bisect_log("requiring bootstrap/app.php");
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
bisect_log("bootstrap done, app class: " . get_class($app));

bisect_log("making kernel");
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
bisect_log("kernel created, class: " . get_class($kernel));

bisect_log("setting up SERVER vars");
$_SERVER['REQUEST_URI'] = '/';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['HTTP_HOST'] = 'localhost';

bisect_log("capturing request");
$request = Illuminate\Http\Request::capture();
bisect_log("request captured");

bisect_log("handling request");
$response = $kernel->handle($request);
bisect_log("response received, status: " . $response->getStatusCode());
echo "status: " . $response->getStatusCode() . "\n";
