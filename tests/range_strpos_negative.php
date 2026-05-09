<?php
print_r(range(1, 5));
print_r(range(5, 1));
print_r(range(0, 10, 2));
print_r(range(10, 0, 2));
print_r(range(1, 1));
print_r(range(0.0, 1.0, 0.25));
print_r(range(1.5, 3.5, 0.5));
print_r(range(3.5, 1.5, 0.5));
print_r(range('a', 'e'));
print_r(range('e', 'a'));
print_r(range('A', 'C'));
print_r(range(1, 5, 2));
print_r(range(0, 10, 3));
print_r(range(0, 1, 0.1));

print_r(array_fill(0, 3, "x"));
print_r(array_fill(2, 3, 0));
print_r(array_fill(-2, 3, "a"));
print_r(array_fill(-3, 4, 1));
print_r(array_fill(0, 0, "x"));
print_r(array_fill_keys(["a", "b", "c"], 0));
print_r(array_fill_keys([1, 5, 10], "y"));

print_r(array_pad([1, 2, 3], 5, 0));
print_r(array_pad([1, 2, 3], -5, 0));
print_r(array_pad([1, 2, 3], 2, 0));
print_r(array_pad([1, 2, 3], 0, 0));
print_r(array_pad(["a"=>1, "b"=>2], 4, 0));
print_r(array_pad(["a"=>1, "b"=>2], -4, 0));

var_dump(strpos("hello world hello", "hello", -5));
var_dump(strpos("hello world hello", "hello", -7));
var_dump(strrpos("hello world hello", "hello", -5));
var_dump(strrpos("hello world hello", "hello", -7));
var_dump(strrpos("abcabcabc", "b", 1));
var_dump(strrpos("abcabcabc", "b", -1));
var_dump(strpos("abc", "x"));
var_dump(strpos("", "x"));
var_dump(strpos("abc", ""));

var_dump(stripos("Hello World", "WORLD"));
var_dump(strripos("Hello World Hello", "hello"));
