<?php
// a compile fatal in eval ends the script; the shutdown functions still run
// and catch what they throw, and the function that failed to compile is
// not declared
class Alive {
    public function __destruct() { echo "destructor\n"; }
}
$alive = new Alive;

register_shutdown_function(function () {
    echo "shutdown\n";
    var_dump(function_exists('broken'));
    try {
        broken(1);
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    $fresh = new Alive;
    unset($fresh);
    echo "after\n";
});

eval('function broken($x): void { return $x; }');
