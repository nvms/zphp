<?php
// an error handler called while include opens its file sees the include in
// its backtrace
function frames(): string {
    $out = [];
    foreach (debug_backtrace() as $f) $out[] = ($f['class'] ?? '') . ($f['type'] ?? '') . $f['function'] . '@' . ($f['line'] ?? '?');
    return implode(' < ', $out);
}
function report($no, $msg) {
    echo explode(':', $msg)[0], ': ', frames(), "\n";
    return true;
}
set_error_handler('report');
include 'zphp_missing_include_file.php';
function loader() {
    return include_once 'zphp_missing_include_other.php';
}
var_dump(loader());

class Thrower {
    static function handle($no, $msg) { throw new Exception('from handler'); }
}
set_error_handler([Thrower::class, 'handle']);
try {
    require 'zphp_missing_include_required.php';
} catch (Exception $e) {
    foreach ($e->getTrace() as $f) echo $f['function'], '@', $f['line'] ?? '?', "\n";
}
// the require's own Error has no such frame
restore_error_handler();
restore_error_handler();
try {
    @require 'zphp_missing_include_required.php';
} catch (Error $e) {
    var_dump(count($e->getTrace()));
}
