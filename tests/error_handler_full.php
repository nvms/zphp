<?php
echo gettype(error_reporting()), "\n";

echo defined("E_ERROR") ? "y" : "n", "\n";
echo defined("E_WARNING") ? "y" : "n", "\n";
echo defined("E_NOTICE") ? "y" : "n", "\n";
echo defined("E_USER_ERROR") ? "y" : "n", "\n";
echo defined("E_USER_WARNING") ? "y" : "n", "\n";
echo defined("E_USER_NOTICE") ? "y" : "n", "\n";
echo defined("E_USER_DEPRECATED") ? "y" : "n", "\n";
echo defined("E_DEPRECATED") ? "y" : "n", "\n";
echo defined("E_PARSE") ? "y" : "n", "\n";
echo defined("E_RECOVERABLE_ERROR") ? "y" : "n", "\n";
echo defined("E_ALL") ? "y" : "n", "\n";

echo E_ERROR, "\n";
echo E_WARNING, "\n";
echo E_PARSE, "\n";
echo E_NOTICE, "\n";
echo E_USER_ERROR, "\n";
echo E_USER_WARNING, "\n";
echo E_USER_NOTICE, "\n";
echo E_USER_DEPRECATED, "\n";
echo E_DEPRECATED, "\n";

$prev = error_reporting(0);
echo gettype($prev), "\n";
$now = error_reporting();
echo $now, "\n";

error_reporting(E_ALL);
echo error_reporting() === E_ALL ? "all" : "no", "\n";

error_reporting($prev);

$captured = [];
set_error_handler(function ($errno, $errstr) use (&$captured) {
    $captured[] = [$errno, $errstr];
    return true;
});

trigger_error("test-warning", E_USER_WARNING);
trigger_error("test-notice", E_USER_NOTICE);
trigger_error("test-deprecated", E_USER_DEPRECATED);
trigger_error("default-notice");

echo count($captured), "\n";
foreach ($captured as $c) echo $c[0], ":", $c[1], "\n";

restore_error_handler();

$called = 0;
set_error_handler(function () use (&$called) {
    $called++;
    return false;
});
@trigger_error("x", E_USER_WARNING);
echo "called=$called\n";
restore_error_handler();

$caught_in = [];
set_error_handler(function ($errno, $errstr) use (&$caught_in) {
    $caught_in[] = $errno;
    return true;
}, E_USER_WARNING | E_USER_NOTICE);

trigger_error("w", E_USER_WARNING);
trigger_error("n", E_USER_NOTICE);
@trigger_error("d", E_USER_DEPRECATED);
echo count($caught_in), " caught\n";

restore_error_handler();

$captured2 = [];
set_error_handler(function ($errno, $errstr) use (&$captured2) {
    $captured2[] = [$errno, $errstr];
    return true;
});
trigger_error("ok", E_USER_NOTICE);
echo count($captured2), "\n";
restore_error_handler();

$h1 = [];
$h2 = [];
set_error_handler(function ($n, $s) use (&$h1) { $h1[] = $s; return true; });
set_error_handler(function ($n, $s) use (&$h2) { $h2[] = $s; return true; });
trigger_error("a", E_USER_NOTICE);
restore_error_handler();
trigger_error("b", E_USER_NOTICE);
restore_error_handler();
print_r($h1);
print_r($h2);

$captured3 = [];
set_error_handler(function ($n, $s) use (&$captured3) {
    $captured3[] = $s;
    return true;
});
trigger_error("loud", E_USER_WARNING);
@trigger_error("quiet", E_USER_WARNING);
echo count($captured3), "\n";
print_r($captured3);
restore_error_handler();

@trigger_error("last-test", E_USER_NOTICE);
$last = error_get_last();
echo gettype($last), "\n";
if (is_array($last)) {
    echo isset($last["type"]) ? "type" : "no", "/";
    echo isset($last["message"]) ? "msg" : "no", "/";
    echo isset($last["file"]) ? "file" : "no", "/";
    echo isset($last["line"]) ? "line" : "no", "\n";
}

error_clear_last();
var_dump(error_get_last());

function inner() {
    return debug_backtrace();
}
function outer() {
    return inner();
}
$bt = outer();
echo gettype($bt), " count=", count($bt) > 0 ? "ok" : "0", "\n";
echo isset($bt[0]["function"]) ? "has-fn" : "no", "\n";

function pbt() {
    debug_print_backtrace();
}
ob_start();
pbt();
$out = ob_get_clean();
echo strlen($out) > 0 ? "has-out" : "empty", "\n";
