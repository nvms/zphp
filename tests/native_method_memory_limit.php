<?php
// a built-in method that runs out of memory ends the script there; the
// caller never continues as if the call had returned
ini_set('log_errors', '0');
ini_set('display_errors', '0');
register_shutdown_function(function () {
    $e = error_get_last();
    // the byte count php reports depends on its allocator
    echo "shutdown: ", strtok($e['message'], '('), "on line ", $e['line'], "\n";
});
ini_set('memory_limit', '16M');
$ar = new SplFixedArray(1);
echo "before\n";
$ar->setSize(10000000);
echo "not reached\n";
