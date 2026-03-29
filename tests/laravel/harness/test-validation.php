<?php
// exercises: form request validation, regex (preg_match), exception handling, JSON error responses

define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// 1. valid request
$request = Illuminate\Http\Request::create('/validate', 'POST', [
    'title' => 'Valid Title',
    'body' => 'Some content here',
    'email' => 'test@example.com',
]);
$request->headers->set('Accept', 'application/json');

$response = $kernel->handle($request);
echo "valid_status: " . $response->getStatusCode() . "\n";
$data = json_decode($response->getContent(), true);
echo "valid: " . ($data['valid'] ? 'true' : 'false') . "\n";
echo "title: " . $data['data']['title'] . "\n";

// 2. invalid request - missing required fields
$request = Illuminate\Http\Request::create('/validate', 'POST', [
    'title' => 'AB',
    'email' => 'not-an-email',
]);
$request->headers->set('Accept', 'application/json');

$response = $kernel->handle($request);
echo "invalid_status: " . $response->getStatusCode() . "\n";
$errors = json_decode($response->getContent(), true);
echo "has_title_error: " . (isset($errors['errors']['title']) ? 'yes' : 'no') . "\n";
echo "has_body_error: " . (isset($errors['errors']['body']) ? 'yes' : 'no') . "\n";
echo "has_email_error: " . (isset($errors['errors']['email']) ? 'yes' : 'no') . "\n";
