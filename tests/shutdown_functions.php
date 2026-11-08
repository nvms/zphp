<?php
// shutdown functions get the arguments they were registered with, can be any
// callable, run when registered by another shutdown function, and hand an
// uncaught exception to the exception handler, which stays installed
class L {
    static function s(...$a) { echo "static ", implode(",", $a), "\n"; }
    function flush($final = false, $x = null) { echo "flush ", var_export($final, true), " ", var_export($x, true), "\n"; }
    private function priv($x) { echo "private $x\n"; }
    function reg() { register_shutdown_function([$this, 'priv'], 'p'); }
}
set_exception_handler(function ($e) { echo "handler ", $e->getMessage(), "\n"; });
$l = new L;
register_shutdown_function([$l, 'flush'], true, 5);
register_shutdown_function('L::s', 1, 2);
register_shutdown_function([new L, 'flush']);
$l->reg();
register_shutdown_function(function ($a) {
    echo "closure $a\n";
    register_shutdown_function(function () {
        echo "nested\n";
        register_shutdown_function('printf', "deep %s\n", 'x');
    });
}, 'arg');
register_shutdown_function('printf', "%s-%s\n", 'a', 'b');
register_shutdown_function(function () { echo "throws\n"; throw new LogicException("in shutdown"); });
register_shutdown_function(function () { echo "after the throw\n"; });
// many registrations from shutdown functions, which grow the list as it runs
for ($i = 0; $i < 300; $i++) {
    register_shutdown_function(function () use ($i) {
        if ($i % 100 == 0) echo "batch $i\n";
        register_shutdown_function(function () use ($i) { if ($i == 299) echo "last\n"; });
    });
}
echo "end\n";
throw new Exception("main");
