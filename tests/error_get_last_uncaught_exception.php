<?php
// error_get_last() in a shutdown function sees the uncaught exception as
// the fatal error php reported it as
register_shutdown_function(function () {
    $last = error_get_last();
    var_dump($last['type']);
    echo $last['message'], "\n";
    var_dump(basename($last['file']), $last['line']);
});

function thrower() {
    throw new DomainException("went wrong");
}
thrower();
