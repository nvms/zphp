<?php
// the uncaught exception is reported and released before the shutdown
// functions run: they throw and catch their own
class Tracked {
    public function __destruct() { echo "argument released\n"; }
}

register_shutdown_function(function () {
    echo "shutdown\n";
    try {
        undefined_function_here();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    try {
        throw new RuntimeException("inner");
    } catch (RuntimeException $e) {
        echo "caught ", $e->getMessage(), "\n";
    }
    echo "after\n";
});

function fail($arg) {
    throw new LogicException("outer");
}
fail(new Tracked);
