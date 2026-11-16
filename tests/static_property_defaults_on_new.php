<?php
// `new` evaluates a class's static property defaults too, also for a class
// with no instance properties, and an error there names the constant
// expression in the trace
function show(Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), " (line ", $e->getLine(), ")\n";
    foreach ($e->getTrace() as $frame) {
        echo "  ", $frame['function'], " at line ", $frame['line'] ?? '-', "\n";
    }
}

class OnlyStatic {
    public static $bar = [
        MISSING_ONE => 'bar',
    ];
}

final class OnlyStaticFinal {
    public static $foo = ['foo' => MISSING_TWO];
}

class WithInstance {
    public static $s = [MISSING_THREE];
    public $i = 1;
}

foreach (['OnlyStatic', 'OnlyStaticFinal', 'WithInstance'] as $class) {
    try {
        new $class();
        echo "created $class\n";
    } catch (Error $e) {
        show($e);
    }
}

define('MISSING_ONE', 'k');
$o = new OnlyStatic();
var_dump(OnlyStatic::$bar);
