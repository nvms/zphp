<?php
// an internal function registered as a shutdown function runs with no
// user code executing: php reports "[no active file]" and line 0
function user_shutdown() {
    echo "user shutdown\n";
    trigger_error("from user code", E_USER_NOTICE);
}
register_shutdown_function('user_shutdown');
register_shutdown_function('trigger_error', 'from the engine', E_USER_NOTICE);
register_shutdown_function(function () {
    try {
        explode();
    } catch (ArgumentCountError $e) {
        echo get_class($e), " at line ", $e->getLine(), "\n";
    }
});
register_shutdown_function('explode');
echo "main\n";
