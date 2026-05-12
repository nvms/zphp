<?php
// WP-cron scheduling API: wp_schedule_event, wp_get_schedules,
// wp_next_scheduled, wp_unschedule_event. exercises sorted-array storage
// and the options table backend.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';
require_once $abspath . 'wp-includes/cron.php';

// minimal i18n stubs - wp_get_schedules uses __() for built-in display
// labels and SHORTINIT doesn't load l10n.php
if (!function_exists('__')) {
    function __($s, $d = null) { return $s; }
}
if (!function_exists('_x')) {
    function _x($s, $c, $d = null) { return $s; }
}

global $wpdb;
$wpdb->query("CREATE TABLE IF NOT EXISTS {$wpdb->options} (
    option_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    option_name VARCHAR(191) NOT NULL DEFAULT '',
    option_value LONGTEXT NOT NULL,
    autoload VARCHAR(20) NOT NULL DEFAULT 'yes',
    PRIMARY KEY (option_id),
    UNIQUE KEY option_name (option_name)
)");

$now = time();

// schedule single
echo 'sched1: ' . (wp_schedule_single_event($now + 60, 'my_one_off') ? 'y' : 'n') . "\n";
echo 'next1: ' . (wp_next_scheduled('my_one_off') > 0 ? 'y' : 'n') . "\n";

// recurring (using built-in 'hourly')
$schedules = wp_get_schedules();
echo 'has-hourly: ' . (isset($schedules['hourly']) ? 'y' : 'n') . "\n";
echo 'has-daily: ' . (isset($schedules['daily']) ? 'y' : 'n') . "\n";
echo 'has-twicedaily: ' . (isset($schedules['twicedaily']) ? 'y' : 'n') . "\n";

echo 'sched-rec: ' . (wp_schedule_event($now + 30, 'hourly', 'my_recurring') ? 'y' : 'n') . "\n";
$next = wp_next_scheduled('my_recurring');
echo 'next-rec-future: ' . ($next > $now ? 'y' : 'n') . "\n";

// schedule with args
echo 'sched-args: ' . (wp_schedule_single_event($now + 90, 'my_with_args', ['key' => 'val', 'n' => 42]) ? 'y' : 'n') . "\n";
echo 'next-args: ' . (wp_next_scheduled('my_with_args', ['key' => 'val', 'n' => 42]) > 0 ? 'y' : 'n') . "\n";
echo 'next-args-mismatch: ' . var_export(wp_next_scheduled('my_with_args', ['other' => 'val']), true) . "\n";

// unschedule
echo 'unsched: ' . (wp_unschedule_event($next, 'my_recurring') ? 'y' : 'n') . "\n";
echo 'after-unsched: ' . var_export(wp_next_scheduled('my_recurring'), true) . "\n";

// add custom schedule
add_filter('cron_schedules', function($schedules) {
    $schedules['every_minute'] = ['interval' => 60, 'display' => 'Every Minute'];
    return $schedules;
});
$schedules = wp_get_schedules();
echo 'custom: ' . (isset($schedules['every_minute']) ? 'y' : 'n') . "\n";
echo 'custom-interval: ' . $schedules['every_minute']['interval'] . "\n";

$wpdb->query("DROP TABLE {$wpdb->options}");
if (file_exists($db_path)) unlink($db_path);
