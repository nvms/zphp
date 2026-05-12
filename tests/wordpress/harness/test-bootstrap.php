<?php
// load the full WordPress bootstrap. SHORTINIT skips the DB and most of the
// runtime so we exercise the autoloader + constant + class registration
// without touching the database.
define('SHORTINIT', true);

// stop wp-load.php from looping for wp-config — point ABSPATH at the app
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

require $abspath . 'wp-load.php';

echo 'ABSPATH: ' . (defined('ABSPATH') ? 'y' : 'n') . "\n";
echo 'WPINC: ' . (defined('WPINC') ? 'y' : 'n') . "\n";
echo 'wp_version is string: ' . (isset($wp_version) && is_string($wp_version) ? 'y' : 'n') . "\n";
echo 'wp_strip_all_tags exists: ' . (function_exists('wp_strip_all_tags') ? 'y' : 'n') . "\n";
echo 'esc_attr exists: ' . (function_exists('esc_attr') ? 'y' : 'n') . "\n";
echo 'esc_html exists: ' . (function_exists('esc_html') ? 'y' : 'n') . "\n";
echo 'sanitize_text_field exists: ' . (function_exists('sanitize_text_field') ? 'y' : 'n') . "\n";
echo 'wp_unslash exists: ' . (function_exists('wp_unslash') ? 'y' : 'n') . "\n";

// pure-function utilities that don't read options/db
echo 'wp_strip_all_tags result: ' . wp_strip_all_tags('<p>hi <b>there</b></p>') . "\n";
echo 'wp_unslash result: ' . wp_unslash("a\\\"b\\\\c") . "\n";
echo 'wp_basename result: ' . wp_basename('/var/www/wp-config.php') . "\n";
