<?php
error_reporting(0);

assert(true);
assert(1 + 1 === 2);
echo "after assert true\n";

try {
    assert(false, new AssertionError("custom message"));
} catch (AssertionError $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

assert_options(ASSERT_ACTIVE, 1);
assert_options(ASSERT_EXCEPTION, 1);
echo assert_options(ASSERT_ACTIVE), "\n";
echo assert_options(ASSERT_EXCEPTION), "\n";

try {
    assert(false);
} catch (AssertionError $e) {
    echo "caught\n";
}

@trigger_error("silenced", E_USER_NOTICE);
echo "after suppressed notice\n";
echo error_get_last()["message"] ?? "none", "\n";

trigger_error("not silenced", E_USER_NOTICE);
echo error_get_last()["message"] ?? "none", "\n";

error_clear_last();
echo error_get_last() === null ? "y" : "n", "\n";

$arr = ["a" => 1];
$x = @$arr["b"];
echo $x ?? "null", "\n";

$file = @file_get_contents("/nonexistent/path");
echo $file === false ? "false" : "ok", "\n";

set_error_handler(function ($n, $s) {
    echo "handler($n): $s\n";
    return true;
}, E_USER_NOTICE | E_USER_WARNING);

trigger_error("notice", E_USER_NOTICE);
trigger_error("warning", E_USER_WARNING);
restore_error_handler();

assert_options(ASSERT_EXCEPTION, 0);
assert(true);
echo "no throw\n";

assert_options(ASSERT_CALLBACK, function ($file, $line, $expr) {
    echo "callback fired\n";
});
assert_options(ASSERT_ACTIVE, 1);
assert_options(ASSERT_EXCEPTION, 0);
assert(false);
echo "after callback\n";

echo defined("E_ERROR") ? "y" : "n", "\n";
echo defined("E_WARNING") ? "y" : "n", "\n";
echo defined("E_NOTICE") ? "y" : "n", "\n";
echo defined("E_DEPRECATED") ? "y" : "n", "\n";
echo defined("E_USER_NOTICE") ? "y" : "n", "\n";
echo defined("E_USER_WARNING") ? "y" : "n", "\n";
echo defined("E_USER_ERROR") ? "y" : "n", "\n";
echo defined("E_USER_DEPRECATED") ? "y" : "n", "\n";
echo defined("E_ALL") ? "y" : "n", "\n";

echo defined("ASSERT_ACTIVE") ? "y" : "n", "\n";
echo defined("ASSERT_CALLBACK") ? "y" : "n", "\n";
echo defined("ASSERT_BAIL") ? "y" : "n", "\n";
echo defined("ASSERT_WARNING") ? "y" : "n", "\n";
echo defined("ASSERT_EXCEPTION") ? "y" : "n", "\n";

@trigger_error("user error caught", E_USER_NOTICE);
echo error_get_last()["message"] ?? "none", "\n";
echo error_get_last()["type"] ?? -1, "\n";
