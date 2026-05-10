<?php
print_r(array_unique([1, 2, 2, 3, 3, 3]));
print_r(array_unique(["a", "b", "a", "c", "b"]));
print_r(array_unique([1, "1", 1.0, "1.0"]));
print_r(array_unique([]));

print_r(array_unique(["a" => 1, "b" => 2, "c" => 1, "d" => 2]));
print_r(array_unique([5 => "x", 10 => "y", 15 => "x"]));

print_r(array_unique([1, "1"], SORT_REGULAR));
print_r(array_unique([1, "1"], SORT_STRING));
print_r(array_unique([1, "1"], SORT_NUMERIC));

print_r(array_unique([1, 2, 1.0, "1", 1.5], SORT_NUMERIC));
print_r(array_unique([1, 2, 1.0, "1", 1.5], SORT_STRING));
print_r(array_unique(["10", "2", "1", "10"], SORT_STRING));
print_r(array_unique(["10", "2", "1", "10"], SORT_NUMERIC));

print_r(array_unique(["foo", "FOO", "bar", "Foo"], SORT_REGULAR));
print_r(array_unique(["foo", "FOO", "bar"], SORT_STRING | SORT_FLAG_CASE));

print_r(array_flip([1, 2, 3]));
print_r(array_flip(["a", "b", "c"]));
print_r(array_flip(["a" => 1, "b" => 2, "c" => 3]));
print_r(array_flip(["a" => "x", "b" => "y", "c" => "x"]));
print_r(array_flip([1, 1, 2, 2]));
print_r(array_flip([]));

print_r(array_count_values([1, 2, 2, 3, 3, 3]));
print_r(array_count_values(["a", "b", "a", "c", "a", "b"]));
print_r(array_count_values([1, "1", 1, "2", 2]));

$arr = [
    "a" => [1, 2],
    "b" => [1, 2],
    "c" => [3, 4],
];
print_r(array_unique($arr, SORT_REGULAR));

$arr = [1, 2, 3, "1", "2"];
print_r(array_count_values($arr));

$big = [];
for ($i = 0; $i < 100; $i++) $big[] = $i % 10;
print_r(array_count_values($big));

$cleaned = array_unique(array_map("strtolower", ["Foo", "FOO", "Bar", "foo"]));
print_r($cleaned);

$names = ["alice", "bob", "alice", "carol", "BOB"];
print_r(array_unique($names));
print_r(array_unique(array_map("strtolower", $names)));

$a = [];
print_r(array_unique($a));
print_r(array_count_values($a));

print_r(array_count_values([1, 2, 3, 4]));

print_r(array_unique(["foo", "FOO", "bar"]));

// array_count_values warning on float values (architectural - PHP emits Warning)

$mixed = [1, "1", 1.0, "1.0", 1.5];
print_r(array_unique($mixed, SORT_REGULAR));

$strs = ["hello", "world", "Hello", "HELLO"];
print_r(array_unique($strs));
print_r(array_unique($strs, SORT_FLAG_CASE | SORT_STRING));
