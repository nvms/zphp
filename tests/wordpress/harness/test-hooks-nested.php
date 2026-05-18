<?php
// WP_Hook sequential + nested invocations. exercises the iterator state
// of WP_Hook::$iterations which is a copy of $this->priorities at the
// start of each apply_filters call. relies on copy-on-assign producing
// an independent array so the second invocation iterates from priority 0
// rather than resuming at end-of-array from the previous run.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

// register filters at distinct priorities so the priorities array has
// non-trivial structure that iterator-state bugs would mis-handle
add_filter('seq', function($v) { return $v . '+a'; }, 10);
add_filter('seq', function($v) { return $v . '+b'; }, 20);
add_filter('seq', function($v) { return $v . '+c'; }, 5);
add_filter('seq', function($v) { return $v . '+d'; }, 15);

// invoke the same filter chain four times - each call must traverse
// every priority bucket independently
for ($i = 1; $i <= 4; $i++) {
    echo "run$i: " . apply_filters('seq', "x$i") . "\n";
}

// nested invocation: one filter triggers another filter chain whose
// priority iteration must not disturb the outer one
add_filter('outer', function($v) { return apply_filters('inner', $v . '[out:'); });
add_filter('outer', function($v) { return $v . ']'; }, 20);
add_filter('inner', function($v) { return $v . 'i1'; }, 10);
add_filter('inner', function($v) { return $v . ',i2'; }, 20);
echo "nested: " . apply_filters('outer', 'start') . "\n";

// recursion guard: filter that calls itself (depth-limited via local counter)
$depth = 0;
add_filter('rec', function($v) use (&$depth) {
    $depth++;
    if ($depth < 3) {
        $v = apply_filters('rec', $v . "($depth)");
    }
    return $v . "*";
});
echo "rec: " . apply_filters('rec', 'r') . "\n";
echo "depth-final: $depth\n";

// add/remove inside the chain - WP supports mid-iteration add via the
// resort_active_iterations mechanism
add_filter('mut', function($v) {
    add_filter('mut', function($v) { return $v . '+late30'; }, 30);
    return $v . '+a10';
}, 10);
add_filter('mut', function($v) { return $v . '+b20'; }, 20);
echo "mut1: " . apply_filters('mut', 'm') . "\n";
echo "mut2: " . apply_filters('mut', 'm') . "\n";

if (file_exists($db_path)) unlink($db_path);
