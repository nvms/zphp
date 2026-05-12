<?php
// exercise WP's hook system (actions and filters) under SHORTINIT. plugin.php
// loads WP_Hook and registers the basic add_filter/apply_filters/add_action/
// do_action infrastructure. real plugins build on top of this.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

add_filter('my_filter', function($v) { return $v . '-one'; });
add_filter('my_filter', function($v) { return $v . '-two'; }, 20);
add_filter('my_filter', function($v) { return $v . '-zero'; }, 5);

$result = apply_filters('my_filter', 'start');
echo "filter result: $result\n";

add_filter('multi_arg', function($v, $a, $b) { return "$v|$a|$b"; }, 10, 3);
$multi = apply_filters('multi_arg', 'base', 'x', 'y');
echo "multi: $multi\n";

$counter = 0;
add_action('my_action', function() use (&$counter) { $counter++; });
add_action('my_action', function() use (&$counter) { $counter += 10; });
do_action('my_action');
echo "counter: $counter\n";

add_action('args_action', function($a, $b) { echo "got: $a, $b\n"; }, 10, 2);
do_action('args_action', 'hello', 'world');

echo "did_action: " . did_action('my_action') . "\n";
echo "has_filter: " . (has_filter('my_filter') ? 'y' : 'n') . "\n";
echo "has_filter unknown: " . (has_filter('nope') ? 'y' : 'n') . "\n";

remove_all_filters('my_filter');
$after_remove = apply_filters('my_filter', 'after');
echo "after remove: $after_remove\n";

if (file_exists($db_path)) unlink($db_path);
