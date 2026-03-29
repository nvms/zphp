<?php
// exercises: Blade template compilation, extract(), file_put_contents/get_contents, htmlspecialchars

define('LARAVEL_START', microtime(true));
require __DIR__ . '/../app/vendor/autoload.php';
$app = require_once __DIR__ . '/../app/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// set up database with test data
$dbPath = __DIR__ . '/../app/database/database.sqlite';
$pdo = new PDO('sqlite:' . $dbPath);
$pdo->exec('DROP TABLE IF EXISTS posts');
$pdo->exec('CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, published INTEGER NOT NULL DEFAULT 0, created_at TEXT, updated_at TEXT)');
$pdo->exec("INSERT INTO posts (title, body, published, created_at, updated_at) VALUES ('Blade Test', 'Template content', 1, '2025-01-01 00:00:00', '2025-01-01 00:00:00')");
$pdo->exec("INSERT INTO posts (title, body, published, created_at, updated_at) VALUES ('Draft Post', 'Not published yet', 0, '2025-01-01 00:00:00', '2025-01-01 00:00:00')");

// clear compiled views
$viewsPath = __DIR__ . '/../app/storage/framework/views';
foreach (glob($viewsPath . '/*.php') as $file) {
    unlink($file);
}

$_SERVER['REQUEST_URI'] = '/posts';
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['HTTP_HOST'] = 'localhost';

$response = $kernel->handle(Illuminate\Http\Request::capture());
echo "status: " . $response->getStatusCode() . "\n";
$content = trim($response->getContent());
$content = preg_replace('/\s+/', ' ', $content);
echo "content: " . $content . "\n";

// show single post
$_SERVER['REQUEST_URI'] = '/posts/1';
$response = $kernel->handle(Illuminate\Http\Request::capture());
echo "show_status: " . $response->getStatusCode() . "\n";
$content = trim($response->getContent());
$content = preg_replace('/\s+/', ' ', $content);
echo "show_content: " . $content . "\n";

// cleanup
$pdo->exec('DROP TABLE IF EXISTS posts');
