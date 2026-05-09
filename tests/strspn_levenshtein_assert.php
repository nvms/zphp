<?php
// strpbrk
echo strpbrk("This is a Simple text.", "mi"), "|\n"; // "is is..." - first char from set
echo strpbrk("This is a Simple text.", "S"), "|\n"; // "Simple text."
var_dump(strpbrk("This is a Simple text.", "Z")); // false
echo strpbrk("hello world", "wo"), "|\n";   // "o world"
echo strpbrk("", "abc") === false ? "empty:false\n" : "empty:str\n";

// strspn / strcspn
echo strspn("42 is the answer", "0123456789"), "\n"; // 2
echo strspn("hello world", "helo"), "\n"; // 5 ("hello")
echo strspn("abcdef", "xyz"), "\n"; // 0
echo strspn("abcdef", "abcdef"), "\n"; // 6
echo strcspn("hello world", " "), "\n"; // 5
echo strcspn("abcdef", "x"), "\n"; // 6
echo strspn("aaaa", "a", 1, 2), "\n"; // 2 (offset 1, length 2)
echo strspn("aaaa", "a", -2), "\n"; // 2 (last 2)
echo strspn("abcdef", "abc", 0, 10), "\n"; // 3 (only 'abc' from start)
echo strcspn("hello", "lo", 0, 3), "\n"; // 2 (he, then l matches)

// similar_text return type
$pct = 0;
$n = similar_text("hello", "world", $pct);
var_dump($n, $pct);
$n = similar_text("php", "php");
var_dump($n);
$n = similar_text("", "abc");
var_dump($n);

// levenshtein with long strings - PHP returns -1 if > 255
$long1 = str_repeat("a", 256);
$long2 = str_repeat("b", 256);
echo levenshtein($long1, $long2), "\n"; // -1
echo levenshtein(str_repeat("a", 255), str_repeat("a", 255)), "\n"; // 0
echo levenshtein(str_repeat("a", 200), str_repeat("b", 200)), "\n"; // 200

// str_word_count format=2 with charlist
print_r(str_word_count("don't can't won't", 2, "'"));   // include ' as word char
print_r(str_word_count("hello-world cool-stuff", 2, "-"));   // - included
print_r(str_word_count("foo123 bar", 2, "0..9")); // include digits

// strtolower/strtoupper edge cases
echo strtolower("Hello"), "\n";
echo strtolower("HELLO"), "\n"; // already
echo strtolower(""), "|\n";
echo strtoupper("hello"), "\n";
echo strtoupper("HELLO"), "\n"; // already
echo strtoupper("MixedCase"), "\n";
echo strtolower("ÉÈ"), "\n"; // PHP byte-based: doesn't lower

// ctype_alnum on bytes
var_dump(ctype_alnum("abc123"));
var_dump(ctype_alnum(""));
var_dump(ctype_alnum("abc 123"));
var_dump(ctype_alnum("abc-123"));

// str_starts/ends_with empty needle
var_dump(str_starts_with("hello", ""));
var_dump(str_ends_with("hello", ""));
var_dump(str_contains("hello", ""));
var_dump(str_starts_with("", ""));
var_dump(str_starts_with("", "x"));

// hash_init / hash_update streaming
$ctx = hash_init("md5");
hash_update($ctx, "hello ");
hash_update($ctx, "world");
echo hash_final($ctx), "\n";
echo hash("md5", "hello world"), "\n"; // should match

$ctx = hash_init("sha256");
hash_update($ctx, "");
echo hash_final($ctx), "\n";

$ctx = hash_init("sha1");
foreach (["abc", "def", "ghi"] as $chunk) hash_update($ctx, $chunk);
echo hash_final($ctx), "\n";
echo hash("sha1", "abcdefghi"), "\n";

// hash_copy
$c1 = hash_init("md5");
hash_update($c1, "hello");
$c2 = hash_copy($c1);
hash_update($c1, " from c1");
hash_update($c2, " from c2");
echo hash_final($c1), "\n";
echo hash_final($c2), "\n";

// assert
assert(true, "should pass");
echo "after assert true\n";
try { assert(false); echo "no err\n"; } catch (\AssertionError $e) { echo "ae:", $e->getMessage(), "\n"; }
try { assert(false, "msg"); echo "no err\n"; } catch (\AssertionError $e) { echo "ae:", $e->getMessage(), "\n"; }
