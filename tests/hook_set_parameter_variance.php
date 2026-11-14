<?php
// a set hook's parameter type must accept the property's type; when the
// classes aren't known at compile time the check runs as the class is
// declared, loading both classes
spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    if ($class === 'P') eval('interface P {}');
    if ($class === 'Q') eval('interface Q extends P {}');
});
eval('class Ok { public Q $p { set(P $v) { echo "set\n"; } } }');
echo "Ok declared\n";
ini_set('fatal_error_backtraces', '0');
eval('class Bad { public P $p { set(Q $value) {} } }');
echo "not reached\n";
