<?php
// covers: nested foreach with by-ref binding, in-place matrix mutation,
//   3D structure mutation, by-ref + key iteration

echo "=== 2D matrix in-place mutation ===\n";
$m = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
];
foreach ($m as &$row) {
    foreach ($row as &$cell) {
        $cell *= 10;
    }
    unset($cell);
}
unset($row);
print_r($m);

echo "=== 3D nesting ===\n";
$cube = [
    'a' => [[1, 2], [3, 4]],
    'b' => [[5, 6]],
];
foreach ($cube as $k => &$slice) {
    foreach ($slice as &$row) {
        foreach ($row as &$v) $v += 100;
        unset($v);
    }
    unset($row);
}
unset($slice);
print_r($cube);

echo "=== by-ref with explicit key (still common pattern) ===\n";
$prices = ['apple' => 1.0, 'banana' => 0.5, 'cherry' => 2.0];
foreach ($prices as $k => &$v) {
    if ($k === 'apple') $v += 0.5;
    if ($k === 'banana') $v *= 2;
}
unset($v);
print_r($prices);

echo "=== triple nesting with mutations at each level ===\n";
$bag = ['x' => ['a' => 1, 'b' => 2], 'y' => ['c' => 3]];
foreach ($bag as $bkey => &$inner) {
    foreach ($inner as $ikey => &$val) {
        $val = "$bkey-$ikey-$val";
    }
    unset($val);
}
unset($inner);
print_r($bag);

echo "=== applying a callback via nested by-ref ===\n";
function squareInPlace(array &$matrix): void {
    foreach ($matrix as &$row) {
        foreach ($row as &$cell) $cell = $cell * $cell;
    }
}
$grid = [[1, 2], [3, 4], [5, 6]];
squareInPlace($grid);
print_r($grid);

echo "=== empty inner arrays don't corrupt outer ===\n";
$m = [[], [1, 2], [], [3]];
foreach ($m as &$row) {
    foreach ($row as &$v) $v *= -1;
    unset($v);
}
unset($row);
print_r($m);

echo "done\n";
