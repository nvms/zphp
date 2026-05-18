<?php
// regression: preg_match/preg_match_all/preg_replace emit PHP-format
// 'Compilation failed: <message> at offset N' warning when the pattern
// is invalid. previously zphp returned false silently. preg_last_error
// is still set to PREG_INTERNAL_ERROR (1) so error_msg / preg_last_error
// userland checks continue to work
$r = preg_match('/[invalid/', 'x');
var_dump($r);
echo preg_last_error() . "\n";

$r = preg_match_all('/(unclosed/', 'x');
var_dump($r);

$r = preg_replace('/[a-/', 'X', 'abc');
var_dump($r);

// valid pattern: no warning, normal return
$r = preg_match('/\d+/', 'abc42def', $m);
echo "$r " . ($m[0] ?? '') . "\n";

// after the bad call, preg_last_error_msg reflects the failure
preg_match('/(/', 'x');
echo preg_last_error_msg() . "\n";
