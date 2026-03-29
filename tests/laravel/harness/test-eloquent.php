<?php
// exercises: Eloquent CRUD, magic methods, query builder, PDO SQLite, collections, model events

define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// create the posts table directly via PDO to avoid needing the console kernel
$dbPath = __DIR__ . '/../app/database/database.sqlite';
$pdo = new PDO('sqlite:' . $dbPath);
$pdo->exec('DROP TABLE IF EXISTS posts');
$pdo->exec('CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, published INTEGER NOT NULL DEFAULT 0, created_at TEXT, updated_at TEXT)');

// helper to make a request through the kernel
function request(string $method, string $uri, array $data = [], array $headers = []): Illuminate\Http\Response|Illuminate\Http\JsonResponse {
    global $kernel;
    $_SERVER['REQUEST_URI'] = $uri;
    $_SERVER['REQUEST_METHOD'] = $method;
    $_SERVER['HTTP_HOST'] = 'localhost';
    $_SERVER['CONTENT_TYPE'] = 'application/x-www-form-urlencoded';
    $_POST = $data;
    $_GET = [];

    $request = Illuminate\Http\Request::capture();
    if (!empty($data) && in_array($method, ['POST', 'PUT', 'PATCH'])) {
        $request = Illuminate\Http\Request::create($uri, $method, $data);
    }

    return $kernel->handle($request);
}

// 1. create a post
$r = request('POST', '/posts', ['title' => 'First Post', 'body' => 'Hello world', 'published' => '1']);
echo "create: " . $r->getStatusCode() . "\n";
$created = json_decode($r->getContent(), true);
echo "created_id: " . $created['id'] . "\n";
echo "created_title: " . $created['title'] . "\n";

// 2. create another post
$r = request('POST', '/posts', ['title' => 'Second Post', 'body' => 'Another one', 'published' => '0']);
echo "create2: " . $r->getStatusCode() . "\n";

// 3. list posts (blade view)
$r = request('GET', '/posts');
echo "list: " . $r->getStatusCode() . "\n";
$content = trim($r->getContent());
// normalize whitespace for comparison
$content = preg_replace('/\s+/', ' ', $content);
echo "list_content: " . $content . "\n";

// 4. show single post
$r = request('GET', '/posts/1');
echo "show: " . $r->getStatusCode() . "\n";
$content = trim($r->getContent());
$content = preg_replace('/\s+/', ' ', $content);
echo "show_content: " . $content . "\n";

// 5. update post
$r = request('PUT', '/posts/1', ['title' => 'Updated Post']);
echo "update: " . $r->getStatusCode() . "\n";
$updated = json_decode($r->getContent(), true);
echo "updated_title: " . $updated['title'] . "\n";

// 6. delete post
$r = request('DELETE', '/posts/2');
echo "delete: " . $r->getStatusCode() . "\n";
$deleted = json_decode($r->getContent(), true);
echo "deleted: " . ($deleted['deleted'] ? 'true' : 'false') . "\n";

// 7. verify only one post remains
$r = request('GET', '/posts');
echo "after_delete: " . $r->getStatusCode() . "\n";
$content = trim($r->getContent());
$content = preg_replace('/\s+/', ' ', $content);
echo "remaining: " . $content . "\n";

// cleanup
$pdo->exec('DROP TABLE IF EXISTS posts');
