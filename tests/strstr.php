<?php

// basic match at start
echo strstr("hello world", "hello") . "\n";

// basic match in middle
echo strstr("hello world", "lo w") . "\n";

// basic match at end
echo strstr("hello world", "world") . "\n";

// single character match
echo strstr("hello world", "o") . "\n";

// no match returns false
var_dump(strstr("hello world", "xyz"));

// no match, substring not present
var_dump(strstr("abcdef", "gh"));

// before_needle=true, match at start
echo strstr("hello world", "hello", true) . "\n";

// before_needle=true, match in middle
echo strstr("hello world", "world", true) . "\n";

// before_needle=true, single char
echo strstr("hello world", "o", true) . "\n";

// before_needle=true, no match
var_dump(strstr("hello world", "xyz", true));

// before_needle=false explicit
echo strstr("hello world", "world", false) . "\n";

// empty haystack
var_dump(strstr("", "needle"));

// needle longer than haystack
var_dump(strstr("hi", "hello world"));

// strchr alias - basic
echo strchr("foo@bar.com", "@") . "\n";

// strchr alias - no match
var_dump(strchr("foo.bar.com", "@"));

// strchr alias - at start
echo strchr("@foo.com", "@") . "\n";

// needle at very start of string
echo strstr("abcdef", "a") . "\n";

// needle at very end of string
echo strstr("abcdef", "f") . "\n";

// multi-byte needle
echo strstr("the quick brown fox", "quick") . "\n";

// multi-byte needle, before_needle
echo strstr("the quick brown fox", "quick", true) . "\n";

// longer multi-byte needle
echo strstr("hello beautiful world", "beautiful") . "\n";

// needle is entire string
echo strstr("exact", "exact") . "\n";

// before_needle when needle is entire string (returns empty)
var_dump(strstr("exact", "exact", true));

// repeated needle, finds first occurrence
echo strstr("abcabcabc", "abc") . "\n";

// before_needle with repeated needle
echo strstr("abcabcabc", "abc", true) . "\n";

// single character haystack, match
echo strstr("x", "x") . "\n";

// single character haystack, no match
var_dump(strstr("x", "y"));

// needle with spaces
echo strstr("hello world test", " world") . "\n";

// before_needle with spaces
echo strstr("hello world test", " world", true) . "\n";

// special characters in needle
echo strstr("path/to/file.txt", "/to/") . "\n";

// email-style parsing
echo strstr("user@example.com", "@") . "\n";
echo strstr("user@example.com", "@", true) . "\n";

// dot-separated
echo strstr("one.two.three", ".two") . "\n";
echo strstr("one.two.three", ".two", true) . "\n";

// newline in string
echo strstr("line1\nline2\nline3", "\n") . "\n";

// before_needle with newline
echo strstr("line1\nline2", "\n", true) . "\n";
