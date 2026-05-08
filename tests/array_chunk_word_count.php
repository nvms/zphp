<?php
// array_chunk size <= 0 throws
try { array_chunk([1,2,3], 0); } catch (\ValueError $e) { echo "z: ", $e->getMessage(), "\n"; }
try { array_chunk([1,2,3], -1); } catch (\ValueError $e) { echo "n: ", $e->getMessage(), "\n"; }

// preserve_keys with int keys
print_r(array_chunk([10=>'a', 20=>'b', 30=>'c', 40=>'d'], 2));
print_r(array_chunk([10=>'a', 20=>'b', 30=>'c', 40=>'d'], 2, true));

// preserve_keys with string keys (always preserved)
print_r(array_chunk(['a'=>1, 'b'=>2, 'c'=>3, 'd'=>4], 2));
print_r(array_chunk(['a'=>1, 'b'=>2, 'c'=>3, 'd'=>4], 2, true));

// chunk size > array
print_r(array_chunk([1,2], 5));
print_r(array_chunk([], 3));

// str_word_count modes
echo str_word_count("Hello World php zig"), "\n";
print_r(str_word_count("Hello World php zig", 1));
print_r(str_word_count("Hello World php zig", 2));
print_r(str_word_count("don't o'malley", 1));
print_r(str_word_count("hello-world", 1, "-"));
echo str_word_count(""), "\n";

// levenshtein cost args
echo levenshtein("kitten", "sitting"), "\n";
echo levenshtein("kitten", "sitting", 1, 1, 1), "\n";
echo levenshtein("kitten", "sitting", 1, 5, 1), "\n";  // higher rep cost
echo levenshtein("abc", "ab", 1, 5, 10), "\n";          // delete cost 10
echo levenshtein("ab", "abc", 1, 5, 10), "\n";          // insert cost 1

// sprintf %g with precision 0 (treats as 1)
echo sprintf("%.0g", 1234.5), "\n";  // 1.0e+3
echo sprintf("%.1g", 1234.5), "\n";  // 1.0e+3
echo sprintf("%.3g", 1234.5), "\n";  // 1.23e+3
echo sprintf("%.3g", 0.000123), "\n"; // 0.000123 -> 0.000123 or 1.23e-4? PHP gives 0.000123
echo sprintf("%.3g", 123456), "\n";   // 1.23e+5
echo sprintf("%g", 123), "\n";        // 123
echo sprintf("%g", 0), "\n";          // 0

// array_diff_key
print_r(array_diff_key(['a'=>1, 'b'=>2, 'c'=>3], ['b'=>0]));
print_r(array_diff_key([1,2,3,4], [0=>'x', 2=>'y']));
print_r(array_diff_key([], ['a'=>1]));
