<?php
function f() {
    $s = PHP_INT_MAX; $s += 1; var_dump($s);
    $t = PHP_INT_MIN; $t -= 1; var_dump($t);
    $m = PHP_INT_MAX; $m *= 2; var_dump($m);
    $f = 1.5; $f *= 2.0; var_dump($f);
    $x = 3; $y = ($x += 4); var_dump($x, $y);
    $z = 2; $z -= $z = 10; var_dump($z);
    $w = 1.5; $w += 1; var_dump($w);
    for ($i = 0, $a = 0; $i < 5; $i++) { $a += $i; $a *= 2; } var_dump($a);
}
f();
