<?php

function f($a, $b, $c, $d = null) {
    return [$a, $b, $c, $d];
}

function g($a, $b, $c, ...$d) {
    return [$a, $b, $c, $d];
}

echo "# All named\n";

$a = f(d: ?, c: ?, b: ?, a: ?);
echo new ReflectionFunction($a), "\n";
var_dump($a(1, 2, 3, 4));

echo "# Some named: Positional first, then named in specified order\n";

$a = f(?, ?, d: ?, c: ?);
echo new ReflectionFunction($a), "\n";
var_dump($a(1, 2, 3, 4));

echo "# Some named, one unspecified\n";

$a = f(?, c: ?, b: ?);
echo new ReflectionFunction($a), "\n";
var_dump($a(1, 2, 3, 4));

echo "# Some named, some implicit added by '...'\n";

$a = f(c: ?, b: ?, ...);
echo new ReflectionFunction($a), "\n";
var_dump($a(1, 2, 3, 4));

echo "# Some named, some implicit added by '...' on variadic function\n";

$a = g(c: ?, b: ?, ...);
echo new ReflectionFunction($a), "\n";
var_dump($a(1, 2, 3, 4, 5, 6));

echo "# Some prebound, some named\n";

$a = f(-1, c: ?, d: -2, b: ?);
echo new ReflectionFunction($a), "\n";
var_dump($a(1, 2));

echo "# Some named, some required missing\n";

try {
    $a = f(b: ?, c: ?);
} catch (Error $e) {
    echo $e::class, ": ", $e->getMessage(), "\n";
}

?>
