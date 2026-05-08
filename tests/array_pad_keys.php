<?php
// array_pad preserves string keys
print_r(array_pad(['a' => 1, 'b' => 2], 4, 'x'));
print_r(array_pad(['k1' => 'v1'], -3, 0));

// integer keys still get reindexed (PHP behavior)
print_r(array_pad([10 => 'a', 20 => 'b'], 4, 'x'));

// mixed keys: strings stay, ints reindex
print_r(array_pad(['a' => 1, 5 => 'x', 'b' => 2], 5, '?'));

// no padding needed
print_r(array_pad(['a' => 1, 'b' => 2], 1, 'z'));
print_r(array_pad([1, 2, 3], 3, 'z'));

// array_is_list
var_dump(array_is_list([]));
var_dump(array_is_list([1, 2, 3]));
var_dump(array_is_list([0 => 'a', 1 => 'b']));
var_dump(array_is_list([1 => 'a', 0 => 'b']));
var_dump(array_is_list(['a' => 1]));
var_dump(array_is_list([0 => 'a', 2 => 'b']));

// hex2bin valid cases
echo bin2hex("hello"), "\n";
var_dump(hex2bin("68656c6c6f"));
var_dump(hex2bin(""));
