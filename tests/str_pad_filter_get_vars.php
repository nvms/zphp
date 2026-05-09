<?php
// str_pad empty pad string throws ValueError
try {
    str_pad("hi", 10, "");
} catch (\ValueError $e) {
    echo "ep: ", $e->getMessage(), "\n";
}

// str_pad with multi-char pad
echo str_pad("hi", 8, "abc"), "|\n";
echo str_pad("hi", 8, "abc", STR_PAD_LEFT), "|\n";
echo str_pad("hi", 8, "abc", STR_PAD_BOTH), "|\n";
echo str_pad("hi", 5), "|\n";  // default space pad

// sprintf custom pad char
echo sprintf("%'*10d", 42), "\n";
echo sprintf("%'_10s", "hi"), "\n";
echo sprintf("%'.10s", "hi"), "\n";
echo sprintf("%'*-10d|", 42), "\n";

// array_filter modes
$arr = ['a' => 1, 'b' => 2, 'c' => 3, 'd' => 4];
print_r(array_filter($arr, fn($v) => $v % 2 === 0));
print_r(array_filter($arr, fn($k) => $k === 'a' || $k === 'c', ARRAY_FILTER_USE_KEY));
print_r(array_filter($arr, fn($v, $k) => $k === 'a' || $v === 4, ARRAY_FILTER_USE_BOTH));
print_r(array_filter([0, 1, '', 'a', false, null, 'b', 2]));

// get_defined_vars in function
function inner() {
    $local1 = 'a';
    $local2 = 42;
    $local3 = [1, 2, 3];
    return get_defined_vars();
}
print_r(inner());

// mt_srand exists (no-op acceptable)
mt_srand(42);
$v = mt_rand(0, 100);
var_dump(is_int($v) && $v >= 0 && $v <= 100);

// getrandmax
var_dump(is_int(mt_getrandmax()));
var_dump(is_int(getrandmax()));

// array_walk_recursive depth
$nested = [1, [2, [3, 4]], 5];
array_walk_recursive($nested, function(&$v, $k) { $v = $v * 10; });
print_r($nested);
