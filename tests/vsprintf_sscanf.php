<?php
// vsprintf
echo vsprintf("%s is %d", ['alice', 30]), "\n";
echo vsprintf('%1$s %2$s %1$s', ['a', 'b']), "\n";
echo vsprintf("%5d", [42]), "\n";

// vprintf
$ret = vprintf("[%d]\n", [42]);
echo "ret:$ret\n";

// sscanf array form
$r = sscanf("alice 30", "%s %d");
print_r($r);

$r = sscanf("2024-01-15", "%d-%d-%d");
print_r($r);

$r = sscanf("3.14", "%f");
print_r($r);

$r = sscanf("ff", "%x");
print_r($r);

// strtr with array
echo strtr("hello world", ['hello' => 'HI', 'world' => 'EARTH']), "\n";
echo strtr("abcabc", ['ab' => 'X', 'bc' => 'Y']), "\n";  // longer match wins
echo strtr("abc", ['a' => 'AA', 'b' => 'BB']), "\n";
echo strtr("abc", []), "\n";

// strtr from/to strings
echo strtr("hello", "el", "ip"), "\n";
echo strtr("ab", "abc", "12"), "\n";

// strtr simultaneous (replacement chars NOT re-replaced)
echo strtr("hello", ['l' => 'X', 'o' => 'l']), "\n";

// strspn
echo strspn("foo123bar", "fo"), "\n";
echo strspn("123abc", "0123456789"), "\n";
echo strspn("aaa", "abc"), "\n";
echo strspn("xyz", "abc"), "\n";
echo strspn("foo", "fo", 0, 2), "\n";
echo strspn("foo", "fo", 1), "\n";

// strcspn
echo strcspn("foo123bar", "0123456789"), "\n";
echo strcspn("abc", "xyz"), "\n";
echo strcspn("foo", "f"), "\n";

// array_count_values (only ints/strings)
print_r(array_count_values([1, 1, 2, 3, 3, 3, "a", "a"]));
print_r(array_count_values(["apple", "banana", "apple", "cherry"]));

// similar_text
similar_text("Hello World", "Hello PHP", $p);
echo round($p, 2), "\n";
echo similar_text("hello", "world"), "\n";
echo similar_text("php", "phpunit"), "\n";

// hex/dec/oct/bin conversions
echo dechex(255), "\n";
echo dechex(0), "\n";
echo hexdec("ff"), "\n";
echo decbin(10), "\n";
echo bindec("1010"), "\n";
echo decoct(8), "\n";
echo octdec("17"), "\n";

// str_repeat edges
echo "[", str_repeat("a", 0), "]\n";
echo "[", str_repeat("", 100), "]\n";
echo strlen(str_repeat("ab", 1000)), "\n";
