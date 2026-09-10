<?php
// call overhead: builtin native vs extension function vs PHP function
function php_add($a, $b) { return $a + $b; }
$n = 2000000;
$t = hrtime(true); for ($i = 0; $i < $n; $i++) { $x = abs($i); } $builtin = (hrtime(true) - $t) / 1e6;
$t = hrtime(true); for ($i = 0; $i < $n; $i++) { $x = demo_add($i, 1); } $ext = (hrtime(true) - $t) / 1e6;
$t = hrtime(true); for ($i = 0; $i < $n; $i++) { $x = php_add($i, 1); } $php = (hrtime(true) - $t) / 1e6;
$t = hrtime(true); for ($i = 0; $i < $n; $i++) { $x = $i + 1; } $loop = (hrtime(true) - $t) / 1e6;
printf("%d calls each, ms: loop %.1f | builtin abs() %.1f | extension demo_add() %.1f | php function %.1f\n", $n, $loop, $builtin, $ext, $php);
