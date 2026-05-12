<?php
// exercise WP's options table, the most-touched table in any real WP install.
// real WP code paths use wpdb to read/write options via SQL, including
// REPLACE INTO and ON DUPLICATE KEY UPDATE, which the SQLite translator
// has to rewrite into SQLite-native upserts.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

global $wpdb;

$wpdb->query("CREATE TABLE IF NOT EXISTS test_options (
    option_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    option_name VARCHAR(191) NOT NULL DEFAULT '',
    option_value LONGTEXT NOT NULL,
    autoload VARCHAR(20) NOT NULL DEFAULT 'yes',
    PRIMARY KEY (option_id),
    UNIQUE KEY option_name (option_name)
)");

$wpdb->insert('test_options', ['option_name' => 'siteurl',  'option_value' => 'https://example.com', 'autoload' => 'yes']);
$wpdb->insert('test_options', ['option_name' => 'blogname', 'option_value' => 'Test Blog',           'autoload' => 'yes']);
$wpdb->insert('test_options', ['option_name' => 'admin_email', 'option_value' => 'admin@test.com',   'autoload' => 'yes']);

$siteurl = $wpdb->get_var($wpdb->prepare("SELECT option_value FROM test_options WHERE option_name = %s LIMIT 1", 'siteurl'));
echo "siteurl: $siteurl\n";

$wpdb->update('test_options', ['option_value' => 'New Title'], ['option_name' => 'blogname']);
$blogname = $wpdb->get_var($wpdb->prepare("SELECT option_value FROM test_options WHERE option_name = %s LIMIT 1", 'blogname'));
echo "blogname: $blogname\n";

$autoloaded = $wpdb->get_results("SELECT option_name, option_value FROM test_options WHERE autoload = 'yes' ORDER BY option_name", ARRAY_A);
foreach ($autoloaded as $opt) {
    echo "autoload: {$opt['option_name']} = {$opt['option_value']}\n";
}

$serialized = serialize(['key' => 'value', 'nested' => ['a', 'b', 'c']]);
$wpdb->insert('test_options', ['option_name' => 'complex_option', 'option_value' => $serialized, 'autoload' => 'no']);
$got_serialized = $wpdb->get_var($wpdb->prepare("SELECT option_value FROM test_options WHERE option_name = %s", 'complex_option'));
$unserialized = unserialize($got_serialized);
echo "complex.key: " . $unserialized['key'] . "\n";
echo "complex.nested[1]: " . $unserialized['nested'][1] . "\n";

$names_like = $wpdb->get_col($wpdb->prepare("SELECT option_name FROM test_options WHERE option_name LIKE %s ORDER BY option_name", 'b%'));
echo "names starting with b: " . implode(',', $names_like) . "\n";

$wpdb->delete('test_options', ['option_name' => 'complex_option']);
$count = $wpdb->get_var("SELECT COUNT(*) FROM test_options");
echo "final count: $count\n";

$wpdb->query("DROP TABLE test_options");
if (file_exists($db_path)) unlink($db_path);
