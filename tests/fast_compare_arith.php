<?php
function f() {
    $n = NAN; $one = 1.0; $i = 1; $s = "10"; $t = "9"; $z = null; $b = true;
    var_dump($n < $one, $n <= $one, $n > $one, $n >= $one, $one <= $n, $one >= $n);
    var_dump($i < $one, $i <= $one, $s < $t, $s <= $t, $s > $t, $s >= $t, $z <= $b);
    var_dump($i == $one, $i == 1, $z == null, $b == true, $b != false, $n == $n, $n != $n, $s == "1e1");
    $c = 0; for ($k = 0.0; $k < 3.5; $k += 0.5) if ($k == 1.5 || $k >= 3.0) $c++; var_dump($c);
    $x = 5; while ($x > 0) { $x -= 2; } var_dump($x);
    var_dump(PHP_INT_MAX + 1, PHP_INT_MIN - 1, PHP_INT_MAX * 3, 1.5 * 2.0, 2.5 - 0.5);
    $a = PHP_INT_MAX; $one = 1; var_dump($a + $one, -$a - $one - $one, $a * $a);
}
f();
