<?php
// the argument functions read the parameters as they are now and the extra
// arguments as passed, and refuse to run outside a function
function attempt(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

function changes($a, $b = "default") {
    $a = "changed";
    unset($b);
    var_dump(func_get_args(), func_get_arg(0), func_get_arg(2), func_num_args());
    try {
        func_get_arg(-1);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        func_get_arg(3);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
changes("original", "second", "extra");

function few($a = 1) {
    var_dump(func_get_args(), func_num_args());
}
few();

function variadic($a, ...$rest) {
    $a = 9;
    var_dump(func_get_args(), func_get_arg(2));
}
variadic(1, 2, 3);

class C {
    public static function make() {
        return get_called_class();
    }
    public function name() {
        return get_called_class();
    }
}
class D extends C {
}
var_dump(D::make(), (new D)->name());
function plain() {
    return get_called_class();
}
attempt('plain');
foreach (['func_get_args()', 'func_get_arg(0)', 'func_num_args()'] as $call) {
    $command = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -r ' . escapeshellarg("try { $call; } catch (Error \$e) { echo \$e->getMessage(); }");
    echo shell_exec($command), "\n";
}
