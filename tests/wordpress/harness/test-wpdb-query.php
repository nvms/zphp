<?php
// boot WP, then run real queries through wpdb (with the SQLite drop-in)
// to verify the database path works end-to-end: DDL, insert, update,
// delete, prepared statements, get_row/get_var/get_col/get_results
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

global $wpdb;

$wpdb->query("CREATE TABLE IF NOT EXISTS test_widgets (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64) NOT NULL, price DECIMAL(8,2))");

$wpdb->insert('test_widgets', ['name' => 'sprocket', 'price' => 12.50]);
$wpdb->insert('test_widgets', ['name' => 'gizmo',    'price' => 4.99]);
$wpdb->insert('test_widgets', ['name' => 'widget',   'price' => 99.00]);

echo 'insert_id last: ' . $wpdb->insert_id . "\n";

$rows = $wpdb->get_results("SELECT name, price FROM test_widgets ORDER BY price ASC", ARRAY_A);
foreach ($rows as $r) {
    echo 'row: ' . $r['name'] . ' / ' . $r['price'] . "\n";
}

$total = $wpdb->get_var("SELECT COUNT(*) FROM test_widgets");
echo "count: $total\n";

$prepared = $wpdb->prepare("SELECT name FROM test_widgets WHERE price > %f", 10.0);
$names = $wpdb->get_col($prepared);
echo 'over-ten names: ' . implode(',', $names) . "\n";

$wpdb->update('test_widgets', ['price' => 13.00], ['name' => 'sprocket']);
$updated_price = $wpdb->get_var($wpdb->prepare("SELECT price FROM test_widgets WHERE name = %s", 'sprocket'));
echo "updated sprocket: $updated_price\n";

$wpdb->delete('test_widgets', ['name' => 'gizmo']);
$final_count = $wpdb->get_var("SELECT COUNT(*) FROM test_widgets");
echo "final count: $final_count\n";

$wpdb->query("DROP TABLE test_widgets");
if (file_exists($db_path)) unlink($db_path);
