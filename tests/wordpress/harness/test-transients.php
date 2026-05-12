<?php
// transient API (set_transient/get_transient/delete_transient) is the most
// commonly used cache primitive in WordPress plugins. it uses the options
// table for storage with two rows per transient (value + timeout). this
// test bootstraps far enough to use the real API, not just raw wpdb.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/option.php';

global $wpdb;

// minimal options-table schema for the transient API
$wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->options} (
    option_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    option_name VARCHAR(191) NOT NULL DEFAULT '',
    option_value LONGTEXT NOT NULL,
    autoload VARCHAR(20) NOT NULL DEFAULT 'yes',
    PRIMARY KEY (option_id),
    UNIQUE KEY option_name (option_name)
)");

// scalar
echo "set-string: " . (set_transient('greeting', 'hello world', 60) ? 'y' : 'n') . "\n";
echo "get-string: " . get_transient('greeting') . "\n";

// array
$data = ['count' => 3, 'items' => ['a', 'b', 'c']];
echo "set-arr: " . (set_transient('mydata', $data, 60) ? 'y' : 'n') . "\n";
$got = get_transient('mydata');
echo "get-arr.count: " . $got['count'] . "\n";
echo "get-arr.items[1]: " . $got['items'][1] . "\n";

// missing key
echo "missing: " . var_export(get_transient('not_set'), true) . "\n";

// delete
echo "delete: " . (delete_transient('greeting') ? 'y' : 'n') . "\n";
echo "after-delete: " . var_export(get_transient('greeting'), true) . "\n";

$wpdb->query("DROP TABLE {$wpdb->options}");
if (file_exists($db_path)) unlink($db_path);
