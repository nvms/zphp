<?php
// $c::m() looks the class up first: a missing class is "Class not found",
// and a class operand that is no string or object is refused

class A {
    static function foo() { return 'foo'; }
    static function __callStatic($n, $a) { return "callStatic $n"; }
}

$ok = 'A';
$abs = '\A';
echo $ok::foo(), "\n", $abs::foo(), "\n", $ok::bar(), "\n";

$missing = 'B';
try {
    $missing::foo();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

spl_autoload_register(function ($c) {
    echo "autoload $c\n";
    if ($c === 'Thrower') throw new Exception("no $c");
});
$t = 'Thrower';
try {
    $t::foo();
} catch (Exception $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$late = 'Late';
try {
    $late::foo();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

foreach ([42, null, [], 1.5] as $bad) {
    try {
        $bad::foo();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
