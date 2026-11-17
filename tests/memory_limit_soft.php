<?php
// memory_limit is a soft limit: the allocation that crosses it succeeds,
// the code goes on to the next interrupt point (here the end of the
// script), and the fatal names the line that allocated
ini_set('log_errors', '0');
ini_set('display_errors', '0');
register_shutdown_function(function () {
    $e = error_get_last();
    echo "shutdown: ", strtok($e['message'], '('), "on line ", $e['line'], "\n";
});
ini_set('memory_limit', '8M');

function grow() {
    $a = str_repeat('a', 3 * 1024 * 1024);
    $b = $a . $a;
    echo "still running\n";
}

grow();
echo "after the call\n";
