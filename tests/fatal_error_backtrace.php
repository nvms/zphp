<?php
// a fatal error is printed with the stack it was raised on, which
// error_get_last() keeps
register_shutdown_function(function () {
    $e = error_get_last();
    echo $e['message'], "\n";
    foreach ($e['trace'] as $frame) echo $frame['function'], ' ', json_encode($frame['args'] ?? null), "\n";
});

function inner($x) {
    trigger_error("stopped here", E_USER_ERROR);
}
function outer($y) {
    inner($y + 1);
}
outer(1);
