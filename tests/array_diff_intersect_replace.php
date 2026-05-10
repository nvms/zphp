<?php
print_r(array_diff([1, 2, 3, 4, 5], [2, 4]));
print_r(array_diff(["a", "b", "c"], ["b"]));
print_r(array_diff(["a" => 1, "b" => 2, "c" => 3], [2]));

print_r(array_intersect([1, 2, 3, 4], [2, 4, 5]));
print_r(array_intersect(["a", "b", "c"], ["b", "c", "d"]));
print_r(array_intersect(["a" => 1, "b" => 2], ["x" => 1, "y" => 9]));

print_r(array_diff_key(["a" => 1, "b" => 2, "c" => 3], ["b" => 0, "c" => 0]));
print_r(array_diff_key(["a" => 1, "b" => 2], ["a" => 99]));

print_r(array_intersect_key(["a" => 1, "b" => 2, "c" => 3], ["b" => 0, "d" => 0]));

print_r(array_diff_assoc(["a" => 1, "b" => 2, "c" => 3], ["a" => 1, "b" => 9]));
print_r(array_intersect_assoc(["a" => 1, "b" => 2], ["a" => 1, "b" => 9]));

print_r(array_diff_ukey(["a" => 1, "b" => 2, "c" => 3], ["A" => 99], "strcasecmp"));

print_r(array_intersect_ukey(["a" => 1, "b" => 2], ["A" => 9, "B" => 8], "strcasecmp"));

print_r(array_uintersect([1, 2, 3], [4, 2], fn($a, $b) => $a - $b));

print_r(array_udiff([1, 2, 3, 4], [2, 4], fn($a, $b) => $a - $b));

print_r(array_uintersect_assoc(["a" => 1, "b" => 2], ["a" => 1, "b" => 9], fn($a, $b) => $a - $b));

print_r(array_udiff_assoc(["a" => 1, "b" => 2, "c" => 3], ["a" => 1, "b" => 9, "c" => 3], fn($a, $b) => $a - $b));

print_r(array_uintersect_uassoc(["a" => 1, "b" => 2], ["A" => 1, "B" => 9], fn($a, $b) => $a - $b, "strcasecmp"));

print_r(array_udiff_uassoc(["a" => 1, "b" => 2], ["A" => 1, "B" => 9], fn($a, $b) => $a - $b, "strcasecmp"));

print_r(array_diff_uassoc(["a" => 1, "b" => 2], ["A" => 1, "B" => 2], "strcasecmp"));

print_r(array_intersect_uassoc(["a" => 1, "b" => 2], ["A" => 1, "B" => 9], "strcasecmp"));

print_r(array_merge_recursive(
    ["a" => 1, "b" => ["x" => 1]],
    ["a" => 2, "b" => ["y" => 2]],
));

print_r(array_merge_recursive(
    ["color" => ["red", "green"]],
    ["color" => ["blue"]],
));

print_r(array_merge_recursive(
    ["k" => 1],
    ["k" => 2],
));

print_r(array_replace(["a" => 1, "b" => 2], ["b" => 99, "c" => 3]));
print_r(array_replace([1, 2, 3], [10]));
print_r(array_replace([1, 2, 3], [], [99]));

print_r(array_replace_recursive(
    ["a" => 1, "b" => ["x" => 1, "y" => 2]],
    ["b" => ["x" => 99, "z" => 3]],
));

print_r(array_replace_recursive(
    ["nest" => [1, 2, 3]],
    ["nest" => [9, 9]],
));

print_r(array_diff([1, 2, "1", "2"], [1])); // loose comparison

print_r(array_intersect([1, 2, "1"], [1])); // loose

print_r(array_diff([1, 2, 3], []));
print_r(array_diff([], [1, 2]));
print_r(array_intersect([1, 2], []));
print_r(array_intersect([], [1, 2]));

print_r(array_diff([1, 2, 3], [2], [1]));
print_r(array_intersect([1, 2, 3, 4], [2, 4], [4]));

print_r(array_unique([1, "1", 1.0, 2, "2", true]));
print_r(array_unique([1, 2, "2", "1"], SORT_STRING));
print_r(array_unique([1, 2, "2", "1"], SORT_NUMERIC));

print_r(array_combine(["a"], [1]));
print_r(array_combine([], []));

print_r(array_flip([1, 2, 3]));

print_r(array_reverse([1, 2, 3], true));
print_r(array_reverse(["a" => 1, "b" => 2]));

print_r(array_keys([1, 2, 1, 3, 1], 1, true));
print_r(array_keys([1, 2, 1, 3, 1], "1", false));
