<?php
// array_walk reads the walked variable again after each callback, as
// php_array_walk does: a new array there is walked from its start, a copy a
// write made goes on where the walk was, and no array at all ends the walk

$array = [1, 2, 3];
array_walk($array, function ($value, $key) {
    echo "$key => $value\n";
    if ($value == 2) $GLOBALS['array'] = [4, 5];
});
var_dump($array);

$array = [1, 2, 3];
$other = [4, 5];
array_walk($array, function (&$value) use ($other) {
    echo "visit $value\n";
    if ($value == 2) $GLOBALS['array'] = $other;
    $value *= 10;
});
var_dump($array, $other);

$list = [1, 2, 3];
array_walk($list, function (&$v, $k) use (&$list) {
    echo "visit $k\n";
    if ($k === 0) {
        $list[] = 99;
        $list[] = 88;
    }
    if ($k === 2) unset($list[1]);
    $v *= 2;
});
print_r($list);

function walkInFunction() {
    $a = ['x' => 1, 'y' => 2];
    array_walk($a, function (&$v, $k) use (&$a) {
        if ($k === 'x') $a = ['p' => 7, 'q' => 8];
        $v += 100;
    });
    print_r($a);
}
walkInFunction();

class Str {
    function __toString(): string {
        global $arr;
        $arr = 1;
        return 'str';
    }
}
$arr = ['k' => new Str];
try {
    array_walk_recursive($arr, 'settype');
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump($arr);

// a walk inside a by-reference foreach over the same array leaves the
// loop where it was
$a = [1, 2, 3, 4, 5];
foreach ($a as &$v) {
    echo "$v\n";
    if ($v == 3) array_walk($a, function (&$x) { $x += 10; });
}
unset($v);
