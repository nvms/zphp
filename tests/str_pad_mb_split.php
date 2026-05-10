<?php
// strcmp returns sign only (-1/0/+1) or specific magnitude
function sign($n) { return $n > 0 ? "+" : ($n < 0 ? "-" : "0"); }

echo sign(strcmp("a", "b")), ":";
echo sign(strcmp("b", "a")), ":";
echo sign(strcmp("a", "a")), "\n";

echo sign(strcmp("apple", "banana")), ":";
echo sign(strcmp("banana", "apple")), "\n";

echo sign(strcasecmp("ABC", "abc")), "\n";
echo sign(strcasecmp("abc", "abd")), ":", sign(strcasecmp("abd", "abc")), "\n";

echo sign(strncmp("hello", "help", 3)), ":";
echo sign(strncmp("hello", "help", 4)), "\n";

echo sign(strncasecmp("Hello", "HELP", 3)), ":";
echo sign(strncasecmp("Hello", "HELP", 4)), "\n";

echo sign(strnatcmp("img2", "img10")), ":";  // - (img2 < img10 naturally)
echo sign(strnatcmp("img10", "img2")), "\n"; // +

echo sign(strnatcasecmp("Img10", "img2")), "\n";

// spaceship
echo sign(1 <=> 2), ":", sign(2 <=> 1), ":", sign(1 <=> 1), "\n";
echo sign("abc" <=> "abd"), "\n";

// str_pad with multibyte (byte-based)
echo str_pad("héllo", 10, "-", STR_PAD_RIGHT), "|\n"; // bytes 6 + 4 = 10
echo strlen(str_pad("héllo", 10, "-", STR_PAD_RIGHT)), "\n";

echo str_pad("a", 8, "héllo", STR_PAD_RIGHT), "|\n"; // pad 7 bytes from "héllo"
echo strlen(str_pad("a", 8, "héllo", STR_PAD_RIGHT)), "\n";

// str_pad LEFT/BOTH
echo str_pad("hi", 6, "*"), "|\n"; // hi**** (default RIGHT)
echo str_pad("hi", 6, "*", STR_PAD_LEFT), "|\n"; // ****hi
echo str_pad("hi", 6, "*", STR_PAD_BOTH), "|\n"; // **hi**
echo str_pad("hi", 7, "*", STR_PAD_BOTH), "|\n"; // **hi*** (extra goes right)

// invalid pad type
try { str_pad("hi", 5, "x", 99); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// empty pad string
try { str_pad("hi", 5, ""); echo "no\n"; } catch (\ValueError $e) { echo "ve-empty\n"; }

// str_pad with negative length
echo str_pad("hi", -5, "*"), "|\n"; // unchanged (length < strlen)
echo str_pad("hi", 1, "*"), "|\n"; // unchanged

// mb_str_split overflow
$s = "abc";
print_r(mb_str_split($s, 5)); // ["abc"]
try { print_r(mb_str_split($s, 0)); echo "no\n"; } catch (\ValueError $e) { echo "ve-zero\n"; }

try { mb_str_split("a", 0); echo "no\n"; } catch (\ValueError $e) { echo "mb-ve\n"; }
try { mb_str_split("a", -1); echo "no\n"; } catch (\ValueError $e) { echo "mb-neg\n"; }

// str_split overflow
print_r(str_split("ab", 5));
try { str_split("a", 0); echo "no\n"; } catch (\ValueError $e) { echo "ss-ve\n"; }
try { str_split("a", -1); echo "no\n"; } catch (\ValueError $e) { echo "ss-neg\n"; }

// mb_str_split with single char chunks
print_r(mb_str_split("héllo")); // single chars

// chunk_split
echo chunk_split("abcdefghij", 3, "-"), "\n"; // abc-def-ghi-j-
echo chunk_split("", 3, "-"), "|\n";

// sprintf %s with various types
echo sprintf("%s", 42), "\n";       // "42"
echo sprintf("%s", 3.14), "\n";     // "3.14"
echo sprintf("%s", true), "\n";     // "1"
echo sprintf("%s", false), "\n";    // ""
echo sprintf("%s", null), "\n";     // ""

// sprintf with object having __toString
class S { public function __toString(): string { return "stringy"; } }
echo sprintf("%s", new S), "\n";

// sprintf %s on array: PHP emits warning + continues (architectural)

// strpos returns int(0) vs false
var_dump(strpos("abc", "a"));     // int(0)
var_dump(strpos("abc", "x"));     // false
echo strpos("abc", "a") === 0 ? "zero\n" : "?\n";
echo strpos("abc", "x") === false ? "false\n" : "?\n";

// trim variants
echo "[", trim("  abc  "), "]\n";
echo "[", trim("0abc0", "0"), "]\n";
echo "[", trim("abc", ""), "]\n"; // PHP 8.4 deprecates? actually no
echo "[", ltrim("xxxhello", "x"), "]\n";
echo "[", rtrim("hellexx", "x"), "]\n";
echo "[", trim("\x00\thello\x00\t\r\n"), "]\n"; // default trims null + whitespace
