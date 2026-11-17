<?php
// running out of memory in code an internal function calls back reports
// the line that allocated, not the internal function's call
ini_set('log_errors', '0');
ini_set('display_errors', '0');
register_shutdown_function(function () {
    $e = error_get_last();
    echo "shutdown: ", strtok($e['message'], '('), "on line ", $e['line'], "\n";
});
ini_set('memory_limit', '16M');

function big() {
    return str_repeat('a', 20 * 1024 * 1024);
}

class C {
    public function __wakeup() {
        big();
        echo "not reached\n";
    }
}

array_map(function ($x) {
    echo "callback $x\n";
}, [1]);
unserialize('O:1:"C":0:{}');
echo "not reached\n";
