<?php
// a by-reference foreach reads its variable again each step: when the
// variable no longer holds an array, the loop ends with php's warning
set_error_handler(function ($no, $msg) { echo "warning: ", $msg, "\n"; return true; });
$a = [42, 43];
foreach ($a as &$c) {
    echo "visit $c\n";
    unset($a[0]);
    $a = null;
}
echo "after null\n";
$b = [1, 2, 3];
foreach ($b as &$v) {
    echo "visit $v\n";
    $b = "now a string";
}
echo "after string\n";
$n = [1, 2];
foreach ($n as &$v) {
    echo "visit $v\n";
    $n = 5;
}
echo "done\n";
