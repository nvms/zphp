<?php
// compact array form
$name = 'alice';
$age = 30;
$city = 'paris';
print_r(compact('name', 'age'));
print_r(compact(['name', 'age']));
print_r(compact('name', ['age', 'city']));

// nested compact
$x = 1; $y = 2; $z = 3;
$keys = ['x', 'y'];
print_r(compact($keys, 'z'));

// extract default (overwrite)
$a = 'old';
extract(['a' => 'new', 'b' => 2]);
echo "$a $b\n";

// extract EXTR_SKIP
$e = 'old';
extract(['e' => 'new', 'f' => 'fnew'], EXTR_SKIP);
echo "$e $f\n";

// extract EXTR_PREFIX_ALL
$arr = ['x' => 1, 'y' => 2];
extract($arr, EXTR_PREFIX_ALL, 'pre');
echo "$pre_x $pre_y\n";

// array_keys with search value
print_r(array_keys(['a' => 1, 'b' => 2, 'c' => 1, 'd' => 2], 1));
print_r(array_keys(['a' => 1, 'b' => '1'], 1, true));
print_r(array_keys(['a' => 1, 'b' => '1'], 1, false));
print_r(array_keys([0, 1, 2, 3, 4, 5], 3));

// array_pop on mixed keys
$a = ['x' => 1, 'y' => 2, 0 => 'z'];
echo array_pop($a), "\n";
print_r($a);
$b = ['p' => 1, 'q' => 2, 'r' => 3];
echo array_pop($b), "\n";
print_r($b);

// levenshtein with cost args
echo levenshtein("kitten", "sitting"), "\n";
echo levenshtein("kitten", "sitting", 1, 1, 1), "\n";
echo levenshtein("kitten", "sitting", 2, 1, 1), "\n";
echo levenshtein("kitten", "sitting", 1, 5, 1), "\n";
echo levenshtein("abc", "ab", 1, 5, 10), "\n";
echo levenshtein("ab", "abc", 1, 5, 10), "\n";
echo levenshtein("", ""), "\n";
echo levenshtein("a", ""), "\n";
echo levenshtein("", "abc"), "\n";

// stream_context_create
$ctx = stream_context_create(['http' => ['method' => 'POST', 'header' => 'X: y']]);
$opts = stream_context_get_options($ctx);
print_r($opts);
