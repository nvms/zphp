<?php
// posts + postmeta: covers JOINs, indexed lookups, and TEXT/LONGTEXT
// round-tripping. exercises the SQLite translator on slightly more complex
// schemas than the options table.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

global $wpdb;

$wpdb->query("CREATE TABLE IF NOT EXISTS test_posts (
    ID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    post_title TEXT NOT NULL,
    post_status VARCHAR(20) NOT NULL DEFAULT 'publish',
    post_date DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00',
    PRIMARY KEY (ID),
    KEY post_status (post_status)
)");

$wpdb->query("CREATE TABLE IF NOT EXISTS test_postmeta (
    meta_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    post_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
    meta_key VARCHAR(255),
    meta_value LONGTEXT,
    PRIMARY KEY (meta_id),
    KEY post_id (post_id),
    KEY meta_key (meta_key)
)");

$wpdb->insert('test_posts', ['post_title' => 'Hello World',  'post_status' => 'publish', 'post_date' => '2026-01-15 10:00:00']);
$p1 = $wpdb->insert_id;
$wpdb->insert('test_posts', ['post_title' => 'Draft Post',   'post_status' => 'draft',   'post_date' => '2026-02-01 12:00:00']);
$p2 = $wpdb->insert_id;
$wpdb->insert('test_posts', ['post_title' => 'Another One',  'post_status' => 'publish', 'post_date' => '2026-03-10 08:30:00']);
$p3 = $wpdb->insert_id;

$wpdb->insert('test_postmeta', ['post_id' => $p1, 'meta_key' => '_thumbnail_id', 'meta_value' => '42']);
$wpdb->insert('test_postmeta', ['post_id' => $p1, 'meta_key' => 'category',      'meta_value' => 'tech']);
$wpdb->insert('test_postmeta', ['post_id' => $p3, 'meta_key' => 'category',      'meta_value' => 'travel']);

$published = $wpdb->get_results(
    "SELECT ID, post_title FROM test_posts WHERE post_status = 'publish' ORDER BY post_date DESC",
    ARRAY_A
);
foreach ($published as $row) {
    echo "published: {$row['ID']} - {$row['post_title']}\n";
}

$joined = $wpdb->get_results($wpdb->prepare(
    "SELECT p.post_title, m.meta_value AS category
     FROM test_posts p
     INNER JOIN test_postmeta m ON p.ID = m.post_id
     WHERE m.meta_key = %s AND p.post_status = %s
     ORDER BY p.post_date DESC",
    'category', 'publish'
), ARRAY_A);
foreach ($joined as $row) {
    echo "cat: {$row['category']} - {$row['post_title']}\n";
}

$count_by_status = $wpdb->get_results(
    "SELECT post_status, COUNT(*) AS n FROM test_posts GROUP BY post_status ORDER BY post_status",
    ARRAY_A
);
foreach ($count_by_status as $row) {
    echo "count {$row['post_status']}: {$row['n']}\n";
}

$big_text = str_repeat('lorem ipsum dolor ', 200);
$wpdb->insert('test_postmeta', ['post_id' => $p2, 'meta_key' => '_blob', 'meta_value' => $big_text]);
$got = $wpdb->get_var($wpdb->prepare("SELECT meta_value FROM test_postmeta WHERE post_id = %d AND meta_key = %s", $p2, '_blob'));
echo "blob len: " . strlen($got) . "\n";
echo "blob match: " . ($got === $big_text ? 'y' : 'n') . "\n";

$wpdb->query("DROP TABLE test_postmeta");
$wpdb->query("DROP TABLE test_posts");
if (file_exists($db_path)) unlink($db_path);
