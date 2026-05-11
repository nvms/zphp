<?php
error_reporting(0);
$h1 = function ($n, $s) { echo "h1\n"; return true; };
$h2 = function ($n, $s) { echo "h2\n"; return true; };
$h3 = function ($n, $s) { echo "h3\n"; return true; };
set_error_handler($h1);
set_error_handler($h2);
set_error_handler($h3);
trigger_error("a", E_USER_NOTICE);
restore_error_handler();
trigger_error("b", E_USER_NOTICE);
restore_error_handler();
trigger_error("c", E_USER_NOTICE);
restore_error_handler();
trigger_error("d", E_USER_NOTICE);
echo "done\n";

set_error_handler(function ($n) { echo "narrow $n\n"; return true; }, E_USER_WARNING);
trigger_error("filtered", E_USER_NOTICE);
trigger_error("seen", E_USER_WARNING);
restore_error_handler();

set_error_handler(function ($errno, $errstr) {
    throw new ErrorException($errstr, 0, $errno);
});
try {
    trigger_error("converted", E_USER_WARNING);
} catch (ErrorException $e) {
    echo "got: ", $e->getMessage(), "\n";
    echo $e->getSeverity(), "\n";
}
restore_error_handler();

echo $h1 instanceof Closure ? "y" : "n", "\n";

$old = set_error_handler(function ($n) { return true; });
echo is_callable($old) ? "y" : "n", "\n";
restore_error_handler();
