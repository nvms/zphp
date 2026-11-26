<?php
// an exception's trace lists eval's frame without an args key, as
// debug_backtrace() does: eval is a language construct
function f($x) {
    eval('try { throw new Exception; } catch (Exception $e) { $GLOBALS["t"] = $e->getTrace(); }');
}
f(1);
foreach ($t as $frame) {
    echo $frame['function'], ' ', array_key_exists('args', $frame) ? json_encode($frame['args']) : 'no args', "\n";
}
