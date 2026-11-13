<?php
// a by-reference foreach iterates the variable's array live: elements
// appended while it runs are visited, removed ones are not, and its place
// survives removals before it

$array = ['foo'];
foreach ($array as $key => &$value) {
    echo $key, " ";
    unset($array[$key]);
    $array[] = 'foo';
    if ($key === 5) break;
}
echo "\n";

$a = ["k" => 0, 1 => 1, 2, 3, 4, 5, 6];
foreach ($a as $k => &$v) {
    if ($k == 1) {
        unset($a[4], $a[5]);
        $a[] = 8;
        $a[] = 9;
    }
    echo "$k => $v\n";
}
unset($v);

$array = [0, 1, 2];
foreach ($array as &$value) {
    echo $value, " ";
    if ($value === 2) {
        unset($array[2], $array[1]);
        $array[1] = 3;
        $array[2] = 4;
    }
}
echo "\n";
unset($value);

$data = ['foo' => 'foo', 'bar' => 'bar', 'baz' => 'baz'];
foreach ($data as $key => &$value) {
    echo $value, " ";
    if ($value === 'foo') {
        unset($data['bar']);
        $data['qux'] = 'qux';
    }
}
echo "\n";
unset($value);

// nested loops over the same array see each other's writes
$a = [1, 2, 3];
foreach ($a as &$x) {
    foreach ($a as &$y) {
        echo "$x-$y ";
        $y++;
    }
}
echo "\n";
unset($x, $y);

// a copy taken in the body doesn't stop the loop or change the copy
$a = [1, 2, 3];
foreach ($a as $k => &$v) {
    $copy = $a;
    if ($k == 0) $a[] = 4;
    $v *= 10;
}
unset($v);
var_dump($a, $copy);

// replacing the array starts over on the new one
$a = [1, 2];
$n = 0;
foreach ($a as &$v) {
    echo $v, " ";
    if ($n++ == 0) $a = [7, 8, 9];
}
echo "\n";
unset($v);

// the internal pointer moves back with removed elements
$array = ['a', 'b', 'c'];
next($array);
next($array);
unset($array[0]);
var_dump(current($array), key($array));

function gen_values() {
    $list = [1, 2];
    foreach ($list as &$item) {
        if ($item < 4) $list[] = $item + 2;
        yield $item;
    }
}
echo implode(",", iterator_to_array(gen_values(), false)), "\n";

function early(array $list) {
    foreach ($list as $k => &$item) {
        if ($k == 1) return $item;
    }
    return null;
}
var_dump(early([5, 6, 7]));
$list = [1, 2, 3];
foreach ($list as &$item) {
    try {
        if ($item == 2) throw new Exception("stop");
    } catch (Exception $e) {
        unset($list[0]);
    }
}
unset($item);
var_dump($list);
