<?php
// array_merge_recursive keeps the next free index of an array it copies
$arr1 = ["key" => [0, 1]];
unset($arr1["key"][1]);
print_r(array_merge_recursive($arr1, ["key" => [2]]));
