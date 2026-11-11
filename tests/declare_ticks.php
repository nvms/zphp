<?php
// declare(ticks=N) runs the registered tick functions every N statements,
// in a block or for the rest of the file; a tick function is never run
// again from inside itself, and can't be unregistered while it runs
$log = [];
function counter($label) {
    global $log;
    $log[] = $label;
}
register_tick_function('counter', 'a');

declare(ticks=1) {
    $x = 1;
    $y = 2;
    if ($x) {
        $z = 3;
    }
}
echo count($log), "\n";

$log = [];
declare(ticks=2) {
    for ($i = 0; $i < 4; $i++) {
        $i;
    }
}
echo count($log), "\n";
unregister_tick_function('counter');

$depth = 0;
$reentrant = function () use (&$depth) {
    $depth++;
    echo "tick at depth $depth\n";
    $depth--;
};
register_tick_function($reentrant);
register_tick_function(function () use ($reentrant) {
    try {
        unregister_tick_function($reentrant);
        echo "unregistered\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
});
declare(ticks=1);
echo "after\n";
