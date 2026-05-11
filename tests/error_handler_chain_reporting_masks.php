<?php
set_error_handler(function ($severity, $msg) {});
restore_error_handler();
echo "ok\n";

$chain = [];
$h1 = function ($sev, $msg) use (&$chain) { $chain[] = "h1:$msg"; };
$h2 = function ($sev, $msg) use (&$chain) { $chain[] = "h2:$msg"; };

set_error_handler($h1);
set_error_handler($h2);

trigger_error("test1", E_USER_NOTICE);
print_r($chain);

restore_error_handler();
$chain = [];

restore_error_handler();

echo "no-handlers\n";

$prev = set_error_handler(fn($sev, $msg) => null);
echo $prev === null ? "y" : "n", "\n";
restore_error_handler();

$captured = [];
set_error_handler(function ($sev, $msg, $file, $line) use (&$captured) {
    $captured[] = ["sev" => $sev, "msg" => $msg];
    return true;
});

trigger_error("a", E_USER_NOTICE);
trigger_error("b", E_USER_WARNING);
trigger_error("c", E_USER_ERROR);

$names = array_map(fn($c) => $c["sev"] . ":" . $c["msg"], $captured);
sort($names);
print_r($names);
restore_error_handler();

echo E_ERROR, " ", E_WARNING, " ", E_NOTICE, "\n";
echo E_USER_ERROR, " ", E_USER_WARNING, " ", E_USER_NOTICE, "\n";

echo E_ALL >= 0 ? "y" : "n", "\n";

error_reporting(E_ALL);
echo error_reporting() === E_ALL ? "y" : "n", "\n";

error_reporting(0);
echo error_reporting(), "\n";

$mask = E_ALL & ~E_NOTICE;
error_reporting($mask);
echo (error_reporting() & E_NOTICE) === 0 ? "y" : "n", "\n";
echo (error_reporting() & E_WARNING) !== 0 ? "y" : "n", "\n";

error_reporting(E_ALL);

set_error_handler(function ($sev, $msg) {
    return true;
}, E_USER_WARNING);

$caught = [];
set_error_handler(function ($sev, $msg) use (&$caught) {
    $caught[] = $msg;
    return true;
}, E_USER_NOTICE);

trigger_error("notice-only", E_USER_NOTICE);
print_r($caught);

restore_error_handler();
restore_error_handler();

set_error_handler(function ($sev, $msg) {
    if (str_starts_with($msg, "skip")) return false;
    echo "handled: $msg\n";
    return true;
});

trigger_error("normal", E_USER_NOTICE);
restore_error_handler();

class AppLogger {
    public array $log = [];
    public function handle($sev, $msg): void {
        $this->log[] = "[$sev] $msg";
    }
}

$logger = new AppLogger;
set_error_handler([$logger, "handle"]);
trigger_error("via-instance", E_USER_NOTICE);
print_r($logger->log);
restore_error_handler();

echo error_get_last() === null ? "null" : "x", "\n";

function triggerAndRestore() {
    set_error_handler(function ($sev, $msg) {
        echo "inner: $msg\n";
        return true;
    });
    trigger_error("from-inner", E_USER_NOTICE);
    restore_error_handler();
}

set_error_handler(function ($sev, $msg) {
    echo "outer: $msg\n";
    return true;
});

triggerAndRestore();
trigger_error("after-inner", E_USER_NOTICE);
restore_error_handler();

$h = function ($sev, $msg) { echo "h:$msg\n"; return true; };
$prev = set_error_handler($h);
echo $prev === null ? "no-prev" : "prev", "\n";
restore_error_handler();

echo function_exists("set_error_handler") ? "y" : "n", "\n";
echo function_exists("restore_error_handler") ? "y" : "n", "\n";
echo function_exists("error_reporting") ? "y" : "n", "\n";
echo function_exists("trigger_error") ? "y" : "n", "\n";
echo function_exists("error_get_last") ? "y" : "n", "\n";

$start_time = error_get_last();
echo $start_time === null || is_array($start_time) ? "y" : "n", "\n";

ini_set("display_errors", 0);
echo ini_get("display_errors") === "0" || ini_get("display_errors") === "" ? "y" : "n", "\n";
ini_set("display_errors", 1);
