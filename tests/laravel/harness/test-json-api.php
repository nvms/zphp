<?php
// exercises: API resources, JsonSerializable, JSON encoding, content-type headers

define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// set up database
$dbPath = __DIR__ . '/../app/database/database.sqlite';
$pdo = new PDO('sqlite:' . $dbPath);
$pdo->exec('DROP TABLE IF EXISTS posts');
$pdo->exec('CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, published INTEGER NOT NULL DEFAULT 0, created_at TEXT, updated_at TEXT)');
$pdo->exec("INSERT INTO posts (title, body, published, created_at, updated_at) VALUES ('API Post', 'API content', 1, '2025-01-01 00:00:00', '2025-01-01 00:00:00')");

// 1. create via API
$request = Illuminate\Http\Request::create('/api/posts', 'POST', [
    'title' => 'New API Post',
    'body' => 'Created via API',
    'published' => '0',
]);
$request->headers->set('Accept', 'application/json');

$response = $kernel->handle($request);
echo "create_status: " . $response->getStatusCode() . "\n";
$data = json_decode($response->getContent(), true);
echo "create_title: " . $data['data']['title'] . "\n";
echo "create_published: " . ($data['data']['published'] ? 'true' : 'false') . "\n";

// 2. list via API
$request = Illuminate\Http\Request::create('/api/posts', 'GET');
$request->headers->set('Accept', 'application/json');

$response = $kernel->handle($request);
echo "list_status: " . $response->getStatusCode() . "\n";
$data = json_decode($response->getContent(), true);
echo "list_count: " . count($data['data']) . "\n";
echo "first_title: " . $data['data'][0]['title'] . "\n";
echo "second_title: " . $data['data'][1]['title'] . "\n";

// cleanup
$pdo->exec('DROP TABLE IF EXISTS posts');
