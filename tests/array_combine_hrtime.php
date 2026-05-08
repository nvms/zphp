<?php
// array_combine with bool/null/float keys
print_r(array_combine([true, false, null], [1, 2, 3]));
print_r(array_combine([1, 2, 3], ['a', 'b', 'c']));
print_r(array_combine(['1', '2', '3'], ['a', 'b', 'c']));   // canonical numeric strings → int
print_r(array_combine(['1abc', '2', 'x'], ['a', 'b', 'c'])); // non-canonical stays string
print_r(array_combine([], []));
print_r(array_combine(['a' => 1, 'b' => 2], ['x', 'y']));

// hrtime
$h = hrtime();
var_dump(is_array($h) && count($h) === 2);
var_dump(is_int($h[0]));
var_dump(is_int($h[1]));
$hi = hrtime(true);
var_dump(is_int($hi));

// usort stability
$data = [
    ['k' => 1, 'v' => 'a'],
    ['k' => 2, 'v' => 'b'],
    ['k' => 1, 'v' => 'c'],
    ['k' => 2, 'v' => 'd'],
    ['k' => 1, 'v' => 'e'],
];
usort($data, fn($x, $y) => $x['k'] <=> $y['k']);
foreach ($data as $r) echo $r['v']; echo "\n";

// uasort stability with equal values
$assoc = ['z' => 1, 'a' => 1, 'b' => 1];
uasort($assoc, fn($x, $y) => $x <=> $y);
print_r($assoc);

// ctype on strings
var_dump(ctype_alpha("hello"));
var_dump(ctype_alpha("héllo"));   // false - non-ASCII
var_dump(ctype_alpha(""));
var_dump(ctype_alnum("abc123"));
var_dump(ctype_alnum("abc123 "));
var_dump(ctype_digit("12345"));
var_dump(ctype_digit("12.34"));
var_dump(ctype_xdigit("abcDEF123"));
var_dump(ctype_xdigit("xyz"));
var_dump(ctype_space("  \t\n"));

// str_contains/starts_with/ends_with empty needle
var_dump(str_contains("abc", ""));
var_dump(str_contains("", ""));
var_dump(str_starts_with("abc", ""));
var_dump(str_ends_with("abc", ""));
var_dump(str_starts_with("", ""));

// microtime
$t1 = microtime();
var_dump(strpos($t1, ' ') !== false);
$t2 = microtime(true);
var_dump(is_float($t2));
