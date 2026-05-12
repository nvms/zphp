<?php
// WP_Rewrite + URL rewriting rules registry. exercises class-heavy code
// and stable internal ordering of rewrite arrays.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/class-wp-rewrite.php';

global $wpdb;
$wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->options} (
    option_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    option_name VARCHAR(191) NOT NULL DEFAULT '',
    option_value LONGTEXT NOT NULL,
    autoload VARCHAR(20) NOT NULL DEFAULT 'yes',
    PRIMARY KEY (option_id),
    UNIQUE KEY option_name (option_name)
)");

$wp_rewrite = new WP_Rewrite();
$wp_rewrite->permalink_structure = '/%year%/%monthnum%/%postname%/';

echo 'using-permalinks: ' . ($wp_rewrite->using_permalinks() ? 'y' : 'n') . "\n";
echo 'index: ' . $wp_rewrite->index . "\n";

$tags = $wp_rewrite->rewritecode;
echo 'has-year: ' . (in_array('%year%', $tags) ? 'y' : 'n') . "\n";
echo 'has-postname: ' . (in_array('%postname%', $tags) ? 'y' : 'n') . "\n";

$wp_rewrite->add_rewrite_tag('%project%', '([^/]+)', 'project=');
echo 'custom-tag: ' . (in_array('%project%', $wp_rewrite->rewritecode) ? 'y' : 'n') . "\n";

$wp_rewrite->add_external_rule('go/([^/]+)/?$', 'external.php?slug=$1');
echo 'ext-count: ' . count($wp_rewrite->extra_rules_top) . "\n";

// rewrite tag translation
$rt = new ReflectionClass($wp_rewrite);
$prop = $rt->getProperty('rewritereplace');
$prop->setAccessible(true);
$replacements = $prop->getValue($wp_rewrite);
echo 'replacements-count-ok: ' . (count($replacements) >= 10 ? 'y' : 'n') . "\n";

$wpdb->query("DROP TABLE {$wpdb->options}");
if (file_exists($db_path)) unlink($db_path);
