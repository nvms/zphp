<?php
// regression: array_walk iterates dynamically (not snapshotted), so any
// elements appended by the callback are visited too. previously zphp
// snapshotted the initial keys so appended entries kept their input value
$arr = [1, 2, 3];
array_walk($arr, function(&$v, $k) use (&$arr) {
    if ($k === 0) $arr[] = 99;
    if ($k === 0) $arr[] = 88;
    $v *= 10;
});
print_r($arr);   // [10, 20, 30, 990, 880]

// removing the current entry during walk: writeback should still apply
// to whatever entry has that key now (or be skipped if it disappeared)
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
array_walk($arr, function(&$v, $k) use (&$arr) {
    if ($k === 'b') unset($arr['c']);   // remove next
    $v *= 100;
});
print_r($arr);   // 'a'=>100, 'b'=>200 (no 'c')

// no-mutation case still works
$arr = [10, 20, 30];
array_walk($arr, function(&$v, $k) { $v += $k; });
print_r($arr);   // [10, 21, 32]
