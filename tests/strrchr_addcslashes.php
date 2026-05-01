<?php

// strrchr - last occurrence
echo strrchr('foo.bar.txt', '.') . "\n";
echo strrchr('user@example.com', '@') . "\n";
echo var_export(strrchr('hello', 'x'), true) . "\n"; // false

// strrchr with before_needle (PHP 8.0+)
echo strrchr('a/b/c/d', '/', true) . "\n";

// addcslashes with single chars
echo addcslashes('hello world!', 'lo!') . "\n";

// addcslashes with range
echo addcslashes('Hello World 2024', 'a..z') . "\n";
echo addcslashes('Hello World 2024', '0..9') . "\n";

// addcslashes with control chars (octal escape)
$s = "tab\tnewline\nbell\x07";
echo addcslashes($s, "\t\n\x07") . "\n";

// stripcslashes roundtrip
$orig = 'simple text';
$slashed = addcslashes($orig, 'a..z');
$back = stripcslashes($slashed);
echo ($back === $orig ? 'roundtrip-ok' : 'roundtrip-fail') . "\n";

// stripcslashes with explicit escapes
echo stripcslashes('hello\\nworld') . "\n";
echo stripcslashes('hex:\\x41\\x42') . "\n";
