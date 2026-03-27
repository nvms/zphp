<?php
// covers: composer autoloading, PSR-7, PSR-15, Slim framework routing,
//   middleware pipeline, request/response objects, namespace resolution,
//   interface implementation, closures as route handlers, dependency injection

require __DIR__ . '/vendor/autoload.php';

use Slim\Factory\AppFactory;
use Slim\Psr7\Factory\ServerRequestFactory;

$app = AppFactory::create();

$app->get('/hello/{name}', function ($request, $response, $args) {
    $response->getBody()->write("Hello, " . $args['name'] . "!");
    return $response;
});

$app->get('/json', function ($request, $response) {
    $data = ['status' => 'ok', 'framework' => 'slim'];
    $response->getBody()->write(json_encode($data));
    return $response->withHeader('Content-Type', 'application/json');
});

$app->post('/echo', function ($request, $response) {
    $body = (string)$request->getBody();
    $response->getBody()->write("echo: " . $body);
    return $response;
});

$factory = new ServerRequestFactory();

$req1 = $factory->createServerRequest('GET', '/hello/world');
$res1 = $app->handle($req1);
echo (string)$res1->getBody() . "\n";
echo "status: " . $res1->getStatusCode() . "\n";

$req2 = $factory->createServerRequest('GET', '/json');
$res2 = $app->handle($req2);
echo (string)$res2->getBody() . "\n";
echo "content-type: " . $res2->getHeaderLine('Content-Type') . "\n";

echo "done\n";
