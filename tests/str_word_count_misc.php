<?php
// string offset assignment
$s = "hello";
$s[0] = "H";
echo $s, "\n"; // Hello
$s[4] = "Z";
echo $s, "\n"; // HellZ
$s[-1] = "Y";
echo $s, "\n"; // HellY

// extending past end pads with spaces
$s = "abc";
$s[5] = "X";
echo "[$s]:", strlen($s), "\n"; // [abc  X]:6

// string offset multi-byte (PHP byte-based)
$s = "héllo"; // h(1) é(2) l(1) l(1) o(1) = 6 bytes
$s[0] = "H";
echo bin2hex($s), "\n";

// string concat with numeric strings
$a = "10" . "20";
echo $a, ":", gettype($a), "\n"; // 1020:string

$a = 10 . 20;
echo $a, ":", gettype($a), "\n"; // 1020:string (concat coerces)

$a = 1.5 . 2.5;
echo $a, ":", gettype($a), "\n"; // 1.52.5:string

$a = "x" . null;
echo "[$a]\n"; // [x]

$a = "x" . true;
echo "[$a]\n"; // [x1]

$a = "x" . false;
echo "[$a]\n"; // [x]

// .= with numeric
$s = 5;
$s .= 3;
echo $s, ":", gettype($s), "\n"; // 53:string

// sprintf precision
echo sprintf("[%.20f]", 1/3), "\n"; // 20-digit precision
echo sprintf("[%.5g]", 1234567.89), "\n"; // 5 sig figs
echo sprintf("[%.0e]", 1234567.89), "\n";
echo sprintf("[%.50f]", 0.1), "\n"; // exposes binary repr

// printf padding precision combos
echo sprintf("[%10.4f]", 3.14), "\n";
echo sprintf("[%-10.4f]", 3.14), "\n";
echo sprintf("[%010.4f]", 3.14), "\n";
echo sprintf("[%+10.4f]", 3.14), "\n";
echo sprintf("[%+010.4f]", -3.14), "\n";

// number_format with empty separators
echo number_format(1234.5678, 2, "", ""), "\n";
echo number_format(1234.5678, 2, ".", ""), "\n";
echo number_format(1234.5678, 0, "", ","), "\n";
echo number_format(0, 2, "", ""), "\n";
echo number_format(-0.5, 0), "\n";

// str_word_count
echo str_word_count(""), "\n"; // 0
echo str_word_count("hello world"), "\n"; // 2
echo str_word_count("don't"), "\n"; // 1 (apostrophe inside)
echo str_word_count("don't can't"), "\n"; // 2
echo str_word_count("hello-world"), "\n"; // 2 (hyphen splits)
echo str_word_count("3 4 5"), "\n"; // 0 (digits aren't words)
echo str_word_count("a3b 4c5"), "\n"; // depends - PHP: 'a' and 'b' from a3b? actually 0

print_r(str_word_count("hello world", 1)); // ["hello", "world"]
print_r(str_word_count("hello world", 2)); // [0=>"hello", 6=>"world"]

// str_word_count with charlist
print_r(str_word_count("hello-world", 1, "-")); // include - in word
print_r(str_word_count("foo123 bar", 1, "0..9")); // include 0-9 range

// invalid format
try { str_word_count("hi", 99); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// chunk_split
echo chunk_split("abcdefghij", 3, "-"), "\n"; // abc-def-ghi-j-
echo chunk_split("abc", 5, "-"), "\n"; // abc-

// wordwrap
echo wordwrap("the quick brown fox", 10, "/", false), "\n";
echo wordwrap("the quick brown fox", 10, "/", true), "\n";
echo wordwrap("verylongword", 5, "/", true), "\n"; // veryl/ongwo/rd
echo wordwrap("verylongword", 5, "/", false), "\n"; // verylongword

// nl2br
echo nl2br("a\nb\r\nc\rd"), "|\n";

// quotemeta
echo quotemeta("$5.99 + tax = ?"), "\n";
echo quotemeta("path/to/file"), "\n";

// strrev edge
echo strrev(""), "|\n";
echo strrev("a"), "\n";
echo strrev("ab"), "\n";

// addslashes / stripslashes round-trip
$orig = "it's \"nice\" \\stuff";
$slashed = addslashes($orig);
$unslashed = stripslashes($slashed);
echo $unslashed === $orig ? "rt-ok\n" : "no\n";

// addcslashes
echo addcslashes("hello world", "lo"), "\n"; // he\l\l\o w\or\ld
echo addcslashes("ABC abc", "A..a"), "\n"; // backslash A-Z and lowercase a
