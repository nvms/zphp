<?php
// WP_Error - WordPress's structured error type, used everywhere.
// pure class, no DB needed.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

$err = new WP_Error('not_found', 'Item not found', ['id' => 42]);
echo 'code: ' . $err->get_error_code() . "\n";
echo 'message: ' . $err->get_error_message() . "\n";
echo 'data.id: ' . $err->get_error_data()['id'] . "\n";

$err->add('invalid_arg', 'Bad argument');
$err->add('rate_limit', 'Too many requests', ['retry_after' => 60]);

echo 'codes-count: ' . count($err->get_error_codes()) . "\n";
echo 'messages-count: ' . count($err->get_error_messages()) . "\n";
echo 'msg-for-invalid: ' . $err->get_error_message('invalid_arg') . "\n";
echo 'data-for-rate: ' . $err->get_error_data('rate_limit')['retry_after'] . "\n";

echo 'is-wp-err: ' . (is_wp_error($err) ? 'y' : 'n') . "\n";
echo 'is-wp-err-on-string: ' . (is_wp_error('not an error') ? 'y' : 'n') . "\n";
echo 'has-errors: ' . ($err->has_errors() ? 'y' : 'n') . "\n";

$err->remove('invalid_arg');
echo 'after-remove-count: ' . count($err->get_error_codes()) . "\n";

$err->add_data(['retry_after' => 120, 'reset' => time() + 120], 'rate_limit');
echo 'all-data-count: ' . count($err->get_all_error_data('rate_limit')) . "\n";

// merge errors
$err2 = new WP_Error('other', 'Another');
$err->merge_from($err2);
echo 'after-merge: ' . count($err->get_error_codes()) . "\n";

// export
$arr = $err->errors;
echo 'export-rate-count: ' . count($arr['rate_limit']) . "\n";

if (file_exists($db_path)) unlink($db_path);
