<?php
// sorting an array that holds a reference to itself (php-src bug63882_2):
// php sorts the buckets in place, so a comparison that looks keys up in the
// array being sorted doesn't find them and doesn't walk into the recursion

$token = [];
$conditions = [];
for ($i = 0; $i <= 2; $i++) {
    $tokens = $conditions;
    $a[0] =& $a;
    $a = unserialize(serialize($GLOBALS));
    $a[0] =& $a;
    $a = unserialize(serialize($GLOBALS));
    $a[0] =& $a;
    foreach ($a as $v) {
        if ($v == 1) {
            try {
                arsort($a);
                echo "sorted\n";
            } catch (Error $e) {
                echo get_class($e), ": ", $e->getMessage(), "\n";
            }
        }
    }
}

$x = ["k" => [1], "z" => [2]];
$x["z"][0] =& $x;
$x["k"][0] =& $x;
try {
    asort($x);
    echo "sorted\n";
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
