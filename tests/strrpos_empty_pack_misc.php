<?php
// printf/sprintf %n$ with reordering
echo sprintf("%2\$s %1\$s %2\$s", "world", "hello"), "\n";
echo sprintf("%1\$03d-%2\$05d", 7, 42), "\n";

// sprintf %s with int (auto coerce)
echo sprintf("[%s]", 42), "\n";
echo sprintf("[%s]", 3.14), "\n";
echo sprintf("[%s]", true), "\n"; // [1]
echo sprintf("[%s]", false), "\n"; // []
echo sprintf("[%s]", null), "\n"; // []

// sprintf with negative ints
echo sprintf("[%d]", -42), "\n";
echo sprintf("[%05d]", -42), "\n";
echo sprintf("[%+05d]", -42), "\n";
echo sprintf("[%-5d]", -42), "\n";

// sprintf %u (unsigned)
echo sprintf("[%u]", -1), "\n"; // PHP: 18446744073709551615 (64-bit unsigned)
echo sprintf("[%u]", 100), "\n";

// pack/unpack basic
$bin = pack("N", 65535); // big-endian uint32
echo bin2hex($bin), "\n"; // 0000ffff
$out = unpack("N", $bin);
echo $out[1], "\n";

$bin = pack("Nn", 65535, 256);
print_r(unpack("Nv1/nv2", $bin));

$bin = pack("v", 256); // little-endian uint16
echo bin2hex($bin), "\n"; // 0001

$bin = pack("a4", "ab"); // null-pad to 4 bytes
echo bin2hex($bin), "\n"; // 61620000

$bin = pack("A4", "ab"); // space-pad
echo bin2hex($bin), "\n"; // 61622020

print_r(unpack("a4", "ab\0\0"));
print_r(unpack("A4", "ab  "));

$bin = pack("c2", -1, 127);
print_r(unpack("c*", $bin));

// hex2bin / bin2hex
echo bin2hex("hi"), "\n"; // 6869
echo hex2bin("6869"), "\n"; // hi

// crc32 / md5 / sha1
echo crc32("hello"), "\n";
echo md5("hello"), "\n";
echo sha1("hello"), "\n";
echo hash("sha256", "hello"), "\n";

// HMAC
echo hash_hmac("sha256", "data", "key"), "\n";
echo hash_hmac("md5", "data", "key"), "\n";
echo hash_hmac("sha1", "", ""), "\n";

// base64 strict / variants
echo base64_encode(""), "|\n";
echo base64_encode("\xff"), "\n"; // /w==
echo base64_decode("SGVsbG8="), "\n"; // Hello
echo base64_decode("SGVsbG8") , "\n"; // Hello (lenient: missing padding)
var_dump(base64_decode("not-valid$$$", true)); // strict false
var_dump(base64_decode("SGVsbG8=", true)); // Hello strict

// rawurlencode / urlencode
echo urlencode("hello world+&=?"), "\n";
echo rawurlencode("hello world+&=?"), "\n";
echo urldecode("hello%20world%2B%26%3D%3F"), "\n";
echo rawurldecode("hello%20world%2B%26%3D%3F"), "\n";

// addcslashes
echo addcslashes("hello world", "lo"), "\n"; // he\l\l\o w\or\ld
echo addcslashes("ABC abc 123", "A..a"), "\n"; // \A\B\C \a\b\c 123
echo addcslashes("\n\t\x07", "\0..\37"), "\n";

// wordwrap edge
echo wordwrap("a b c", 1, "/", false), "\n"; // a/b/c
echo wordwrap("ab cd", 1, "/", true), "\n"; // a/b/c/d
echo wordwrap("ab", 1, "/", true), "\n"; // a/b

// chunk_split
echo chunk_split("abc", 2), "\n"; // ab\r\nc\r\n
echo chunk_split("abcd", 2, "-"), "\n"; // ab-cd-

// nl2br
echo nl2br("a\nb"), "\n";
echo nl2br("a\rb"), "\n";
echo nl2br("a\r\nb"), "\n";
echo nl2br("a", false), "\n";

// quoted_printable
echo quoted_printable_encode("héllo"), "\n";
echo quoted_printable_decode("h=C3=A9llo"), "\n";

// number_format edge
echo number_format(123456789.12345, 4, '.', ','), "\n";
echo number_format(0.0001), "|\n";
echo number_format(0.0001, 5), "\n";
try { echo number_format(1.0/0.0 ** 2, 2), "|\n"; } catch (\DivisionByZeroError $e) { echo "div0\n"; }

// strpos variants
var_dump(strpos("abcdef", "cd"));
var_dump(strpos("abcdef", "cd", 3));
var_dump(strpos("abcdef", "x"));
var_dump(strpos("", "x"));
var_dump(strpos("abc", ""));

// strrpos
var_dump(strrpos("abcabc", "b"));
var_dump(strrpos("abcabc", "b", -2));
var_dump(strrpos("abc", ""));
