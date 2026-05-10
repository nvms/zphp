<?php
echo substr("hello", 0), "\n";    // hello
echo substr("hello", 1), "\n";    // ello
echo substr("hello", -1), "\n";   // o
echo substr("hello", -3), "\n";   // llo
echo substr("hello", -10), "\n";  // hello
echo substr("hello", 10), "\n";   // ""
var_dump(substr("hello", 5));      // "" (empty string at boundary)
var_dump(substr("hello", 6));      // "" (PHP 8+)

echo "[", substr("hello", 0, 0), "]\n";
echo "[", substr("hello", 1, 0), "]\n";

echo substr("hello", 0, 3), "\n";  // hel
echo substr("hello", 0, 5), "\n";  // hello
echo substr("hello", 0, 100), "\n"; // hello

echo substr("hello", 0, -1), "\n"; // hell
echo substr("hello", 0, -3), "\n"; // he
echo substr("hello", 0, -5), "\n"; // ""
echo substr("hello", 0, -10), "\n"; // ""

echo substr("hello", 1, -1), "\n"; // ell
echo substr("hello", -3, 2), "\n"; // ll
echo substr("hello", -3, -1), "\n"; // ll

var_dump(substr("", 0));
var_dump(substr("", 0, 5));

echo substr("a", 0), "\n";
echo substr("a", 1), "\n";
echo substr("a", -1), "\n";
echo substr("a", 0, 1), "\n";

// str_replace with arrays
echo str_replace(["a", "b"], ["X", "Y"], "abc"), "\n";  // XYc
echo str_replace(["a", "b"], "Z", "abc"), "\n";          // ZZc
try { echo str_replace("a", ["X", "Y"], "abc"), "\n"; } catch (\TypeError $e) { echo "te\n"; }

// fewer replacements than searches: extras get ""
echo str_replace(["a", "b", "c"], ["X", "Y"], "abcd"), "\n"; // XYd

// search empty string (no replacement)
echo str_replace("", "X", "abc"), "\n"; // abc

// chained replacement: process pairs sequentially
echo str_replace(["a", "b"], ["b", "X"], "ab"), "\n"; // bX -> XX (a→b first, then b→X applied)

// case insensitive
echo str_ireplace(["A", "B"], ["x", "y"], "abABc"), "\n"; // xyxyc

// count
$count = 0;
str_replace(["a", "b"], "_", "ababab", $count);
echo $count, "\n"; // 6

// preg_split
print_r(preg_split('/,/', "a,b,c,d,e"));
print_r(preg_split('/,/', "a,b,c,d,e", 3));   // limit
print_r(preg_split('/,/', "a,b,c,d,e", 0));   // 0 = treat as no limit but PHP says no limit, actually PHP treats 0 as 1
print_r(preg_split('/,/', "a,b,c,d,e", -1));  // -1 = no limit
print_r(preg_split('/,/', "", -1));            // [""]
print_r(preg_split('/,/', "abc", -1));         // ["abc"]

// limit affects last element
print_r(preg_split('/,/', "a,b,c,d,e", 2));    // ["a", "b,c,d,e"]
print_r(preg_split('/,/', "a,b,c,d,e", 1));    // ["a,b,c,d,e"]

// PREG_SPLIT_NO_EMPTY
print_r(preg_split('/,/', "a,,b,,c,", -1, PREG_SPLIT_NO_EMPTY));

// empty pattern (split between every char)
print_r(preg_split('//', "hello"));            // ["", "h", "e", "l", "l", "o", ""]
print_r(preg_split('//', "hello", -1, PREG_SPLIT_NO_EMPTY));

// str_pad multi-byte
echo str_pad("abc", 5, "-"), "\n";       // abc--
echo str_pad("abc", 5, "-", STR_PAD_LEFT), "\n";
echo str_pad("abc", 6, "-", STR_PAD_BOTH), "\n";
echo str_pad("abc", 7, "xy", STR_PAD_BOTH), "\n"; // "xyabcxy" or similar
echo str_pad("abc", 10, "12345"), "\n";

// str_pad shorter than original - returns original
echo str_pad("hello", 3, "*"), "\n"; // hello

// str_pad with pad string longer than diff
echo str_pad("a", 5, "12345"), "\n"; // a1234 (truncated pad)

// mb_substr
echo mb_substr("hello", 0, 3), "\n";
echo mb_substr("héllo", 1, 3), "\n";
echo mb_substr("héllo", 0), "\n";
echo mb_substr("café", -2), "\n";

// mb_strlen
echo mb_strlen("hello"), "\n";    // 5
echo mb_strlen("héllo"), "\n";    // 5
echo mb_strlen("café"), "\n";     // 4
echo mb_strlen(""), "\n";          // 0
echo strlen("héllo"), "\n";        // 6 (bytes)

// mb_str_split
print_r(mb_str_split("hello"));
print_r(mb_str_split("hello", 2));
print_r(mb_str_split("café"));

// substr_count
echo substr_count("abcabcabc", "abc"), "\n"; // 3
echo substr_count("aaa", "aa"), "\n"; // 1 (non-overlapping)
echo substr_count("hello world", "o"), "\n"; // 2
echo substr_count("hello", "xyz"), "\n"; // 0

// substr_count with offset/length
echo substr_count("aaaaaa", "aa", 1), "\n"; // 2 (start at 1)
echo substr_count("aaaaaa", "aa", 0, 4), "\n"; // 2 (within first 4 chars)

// strpos / strrpos with offset
echo strpos("abcabc", "b"), "\n";    // 1
echo strpos("abcabc", "b", 2), "\n"; // 4
echo strrpos("abcabc", "b"), "\n";   // 4
echo strrpos("abcabc", "b", -3), "\n"; // 1

// stripos / strripos
echo stripos("ABCabc", "b"), "\n"; // 1

// str_contains / str_starts_with / str_ends_with
var_dump(str_contains("hello world", "world"));
var_dump(str_contains("hello", "yo"));
var_dump(str_starts_with("https://example.com", "https://"));
var_dump(str_ends_with("file.txt", ".txt"));
var_dump(str_ends_with("file.txt", ".js"));

// str_split
print_r(str_split("hello"));
print_r(str_split("hello", 2));
print_r(str_split("hello", 100));
print_r(str_split("", 1));

// strtr with single char replacements
echo strtr("hello", "el", "ip"), "\n";

// strtr with array
echo strtr("hello world", ["hello" => "hi", "world" => "earth"]), "\n";

// strtr longest match wins
echo strtr("aab", ["a" => "X", "aa" => "Y"]), "\n"; // Yb (aa beats a)

// trim variants
echo "[", trim("  hello  "), "]\n";
echo "[", trim("--hello--", "-"), "]\n";
echo "[", ltrim("  hello  "), "]\n";
echo "[", rtrim("  hello  "), "]\n";

// number formatting
echo number_format(1234.5678), "\n";      // 1,235
echo number_format(1234.5678, 2), "\n";    // 1,234.57
echo number_format(1234.5678, 2, ".", ","), "\n";
echo number_format(0.5), "\n"; // 1 (half away from 0)

// printf vs sprintf
$out = sprintf("%05d %.2f %-10s|", 42, 3.14, "left");
echo $out, "\n";
