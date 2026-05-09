<?php
// sscanf basic
var_dump(sscanf("age 42", "age %d"));
var_dump(sscanf("42 23.5 hello", "%d %f %s"));
// width specifier
var_dump(sscanf("12345", "%3d%2d"));
// hex
var_dump(sscanf("ff 0x1A", "%x %x"));
// octal
var_dump(sscanf("0755", "%o"));
// char class
var_dump(sscanf("hello world", "%[a-z] %[a-z]"));
// negation
var_dump(sscanf("abc123def", "%[^0-9]%d%[^0-9]"));
// %c (single char)
var_dump(sscanf("ABC", "%c%c%c"));
// %s stops at whitespace
var_dump(sscanf("  hi   bye  ", "%s %s"));
// literal
var_dump(sscanf("Year: 2025", "Year: %d"));
// ref args
$n = 0; $s = "";
$r = sscanf("foo 7", "%s %d", $n, $s);
var_dump($r, $n, $s);
// no match
var_dump(sscanf("abc", "%d"));
// fewer fields than format
var_dump(sscanf("12", "%d %d"));
// extra characters
var_dump(sscanf("12abc", "%d"));
// %% literal
var_dump(sscanf("50%", "%d%%"));
// negative
var_dump(sscanf("-42", "%d"));
// float forms
var_dump(sscanf("1.5e2", "%f"));
var_dump(sscanf(".5 5.", "%f %f"));
// %s with width
var_dump(sscanf("hello", "%3s"));
