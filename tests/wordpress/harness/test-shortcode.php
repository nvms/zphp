<?php
// shortcode API: every WP plugin that hooks content uses this. exercises
// regex parsing, callbacks, and the way WP shells out from filter to
// shortcode handler.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/shortcodes.php';

add_shortcode('hello', function($atts) {
    $atts = shortcode_atts(['name' => 'world', 'punct' => '!'], $atts);
    return "Hi, {$atts['name']}{$atts['punct']}";
});

add_shortcode('upper', function($atts, $content) {
    return strtoupper($content);
});

add_shortcode('repeat', function($atts, $content) {
    $atts = shortcode_atts(['times' => 2], $atts);
    return str_repeat($content, (int) $atts['times']);
});

echo do_shortcode("Greeting: [hello name='Alice']") . "\n";
echo do_shortcode("Default: [hello]") . "\n";
echo do_shortcode("Mixed: [hello name=Bob punct=.] and [hello]") . "\n";
echo do_shortcode("Wrap: [upper]hello world[/upper]") . "\n";
echo do_shortcode("Inner: [repeat times=3]ab[/repeat]") . "\n";
echo do_shortcode("Escaped: [[hello]]") . "\n";

echo "has-hello: " . (shortcode_exists('hello') ? 'y' : 'n') . "\n";
echo "has-nope: " . (shortcode_exists('nope') ? 'y' : 'n') . "\n";

remove_shortcode('hello');
echo "after-remove: " . do_shortcode("[hello]") . "\n";

if (file_exists($db_path)) unlink($db_path);
