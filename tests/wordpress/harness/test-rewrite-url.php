<?php
// URL/rewrite helpers: add_query_arg, remove_query_arg, esc_url, sanitize_url,
// home_url path, wp_parse_url. these are pure-string functions touched by
// every theme and plugin.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/http.php';

echo add_query_arg('foo', 'bar', 'https://x.com/page') . "\n";
echo add_query_arg(['a' => 1, 'b' => 2], 'https://x.com/page?z=9') . "\n";
echo remove_query_arg('a', 'https://x.com/page?a=1&b=2&c=3') . "\n";
echo remove_query_arg(['a', 'b'], 'https://x.com/page?a=1&b=2&c=3') . "\n";

$p = wp_parse_url('https://user:pass@example.com:8080/path/to/file.php?q=1&r=2#frag');
echo "scheme: " . $p['scheme'] . "\n";
echo "host: " . $p['host'] . "\n";
echo "port: " . $p['port'] . "\n";
echo "path: " . $p['path'] . "\n";
echo "query: " . $p['query'] . "\n";
echo "fragment: " . $p['fragment'] . "\n";
echo "user: " . $p['user'] . "\n";


if (file_exists($db_path)) unlink($db_path);
