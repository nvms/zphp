<?php
// call arguments in traces: floats with the precision ini and a fraction,
// and an include that a failing call is made from names its file

function f($a) { throw new Exception("x"); }

foreach ([1.0, 0.1 + 0.2, -0.0, 1e25, 2.5, NAN, INF, 1e-7] as $v) {
    try {
        f($v);
    } catch (Exception $e) {
        echo $e->getTraceAsString(), "\n";
    }
}

try {
    require __DIR__ . '/fixtures/trace_include_call.php';
} catch (TypeError $e) {
    echo str_replace(__DIR__, 'DIR', $e->getTraceAsString()), "\n";
}
