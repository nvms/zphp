<?php
// a by-reference foreach whose variable is rebound to an array another
// variable holds separates it before going on there, from its start
$b = [1, 2];
$a = [0];
foreach ($a as &$v) {
    if ($v === 0) $a = $b; else $v *= 10;
}
unset($v);
var_dump($a, $b);

$a = [1, 2, 3];
foreach ($a as &$v) { echo $v, " "; if ($v == 2) $a = [7, 8, 9]; }
echo "\n";
unset($v);
$a = [1, 2, 3];
foreach ($a as &$v) { echo $v, " "; if ($v == 2) { $b = $a; $a[] = 4; } }
echo "\n";
unset($v);

// the inner loop goes back to the start each time its variable is given
// the outer array again (GH-19613)
$a = [1];
$i = 0;
foreach ($a as $ok => &$v) {
    echo "outer $ok\n";
    $a[0] = $a;
    foreach ($v as $k => &$w) {
        echo "inner $k ", count($v), "\n";
        $w = $a;
        if ($i++ == 6) {
            break 2;
        }
    }
}
echo "done\n";
