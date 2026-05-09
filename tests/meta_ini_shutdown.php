<?php
// str_pad with empty pad string
try { str_pad("hi", 10, ""); echo "no err\n"; } catch (\ValueError $e) { echo "v\n"; }

// sprintf %s with int
echo sprintf("%s", 42), "|\n";
echo sprintf("%s", 3.14), "|\n";
echo sprintf("%s", true), "|\n"; // "1"
echo sprintf("%s", false), "|\n"; // ""
echo sprintf("%s", null), "|\n"; // ""

// debug_backtrace
function foo() { return debug_backtrace(); }
function bar() { return foo(); }
function baz() { return bar(); }
$bt = baz();
echo count($bt), "\n";
foreach ($bt as $f) echo $f['function'], " ";
echo "\n";

// debug_backtrace with skip flags
function inner() { return debug_backtrace(0, 2); }
function outer() { return inner(); }
function root() { return outer(); }
$bt = root();
echo count($bt), "\n";
foreach ($bt as $f) echo $f['function'], " ";
echo "\n";

// debug_print_backtrace
function tracer() { ob_start(); debug_print_backtrace(); $s = ob_get_clean(); return $s; }
$out = tracer();
echo strlen($out) > 0 ? "ok\n" : "empty\n";

// ini_get/ini_set
echo ini_get("memory_limit"), "\n";
echo ini_get("display_errors"), "\n";
$old = ini_set("display_errors", "0");
echo ini_get("display_errors"), "\n";
ini_set("display_errors", $old);

// error_reporting
$old = error_reporting();
error_reporting(E_ALL);
echo error_reporting() === E_ALL ? "all\n" : "diff\n";
error_reporting(0);
echo error_reporting() === 0 ? "zero\n" : "diff\n";
error_reporting($old);

// set_error_handler chain return
$results = [];
set_error_handler(function($errno, $msg) use (&$results) {
    $results[] = "h1:$msg";
    return false; // returning false propagates to default
});
@trigger_error("warn1", E_USER_WARNING);
restore_error_handler();
print_r($results);

// register_shutdown_function order
register_shutdown_function(function() { echo "[s1]\n"; });
register_shutdown_function(function() { echo "[s2]\n"; });
register_shutdown_function(function() { echo "[s3]\n"; });
echo "[main-end]\n";

// gc_collect_cycles - returns int (count of collected cycles)
$n = gc_collect_cycles();
var_dump(is_int($n));

// memory_get_usage
$m = memory_get_usage();
var_dump(is_int($m) && $m > 0);
$mp = memory_get_peak_usage();
var_dump(is_int($mp) && $mp > 0);

// microtime
$mt_str = microtime();
$mt_float = microtime(true);
var_dump(is_string($mt_str));
var_dump(is_float($mt_float));
echo str_word_count($mt_str), "\n"; // "0.123 1234567890" -> 2 numbers? actually word_count counts alpha words

// lcfirst
echo lcfirst("Hello"), "\n";
echo lcfirst("ABCD"), "\n";
echo ucfirst("hello world"), "\n";
echo ucfirst("HELLO"), "\n";
echo lcfirst(""), "|\n";
echo ucfirst(""), "|\n";

// sprintf with mismatched types
echo sprintf("%d", "5abc"), "\n";   // 5
echo sprintf("%d", "abc"), "\n";   // 0
echo sprintf("%d", "  10  "), "\n";   // 10
echo sprintf("%d", "1e3"), "\n";   // 1000? or 1?
echo sprintf("%f", "3.14"), "\n";   // 3.140000
echo sprintf("%05d", -5), "\n";   // -0005 (PHP 8)
echo sprintf("%-5d|", 42), "\n";   // "42   |"
echo sprintf("%+5d", 42), "\n";   // "  +42"
echo sprintf("% 5d", 42), "\n";   // "   42" (space flag)
