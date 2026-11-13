<?php
// the scope introspection functions refuse dynamic calls, and a dynamic
// static call checks its class before its method name

function scoped() {
    $x = 1;
    foreach (['extract', 'compact', 'get_defined_vars', 'func_get_args', 'func_get_arg', 'func_num_args', 'EXTRACT'] as $f) {
        foreach ([fn() => $f(['x' => 2]), fn() => call_user_func($f, ['x' => 2]), fn() => array_map($f, [['x' => 2]])] as $call) {
            try {
                $call();
                echo "$f ran\n";
            } catch (Error $e) {
                echo get_class($e), ': ', $e->getMessage(), "\n";
            }
        }
    }
    // a direct call still works, and a dynamic call of anything else
    var_dump(compact('x'), func_num_args());
    $g = 'strtoupper';
    var_dump($g('ok'));
}
scoped(1, 2);

class K {
    public static function m() { return 'K::m'; }
}
$o = new K;
foreach ([[$o, $o], [$o, 1], [1, 'm'], [null, 'm'], ['K', 'm'], [$o, 'm']] as [$c, $m]) {
    try {
        var_dump($c::$m());
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        var_dump($c::$m(...[]));
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
try {
    var_dump(K::$o());
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
