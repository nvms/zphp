<?php

// strcasecmp
echo strcasecmp("Hello", "hello") . "\n";
echo strcasecmp("abc", "ABC") . "\n";
echo strcasecmp("abc", "abd") < 0 ? "neg" : "pos";
echo "\n";
echo strcasecmp("abd", "abc") > 0 ? "pos" : "neg";
echo "\n";
echo strcasecmp("", "") . "\n";
echo strcasecmp("a", "") > 0 ? "pos" : "neg";
echo "\n";

// strncasecmp
echo strncasecmp("Hello World", "hello earth", 5) . "\n";
echo strncasecmp("abcdef", "ABCXYZ", 3) . "\n";
echo strncasecmp("abcdef", "ABCXYZ", 4) < 0 ? "neg" : "pos";
echo "\n";
echo strncasecmp("abc", "abc", 0) . "\n";

// substr_compare
echo substr_compare("abcdef", "bcd", 1, 3) . "\n";
echo substr_compare("abcdef", "BCD", 1, 3, true) . "\n";
echo substr_compare("abcdef", "def", 3) . "\n";
echo substr_compare("abcdef", "xyz", 3) < 0 ? "neg" : "pos";
echo "\n";
echo substr_compare("abcdef", "bc", 1, 2) . "\n";

// str_contains edge cases
echo var_export(str_contains("hello", ""), true) . "\n";
echo var_export(str_contains("", ""), true) . "\n";
echo var_export(str_contains("", "a"), true) . "\n";
echo var_export(str_contains("abc", "abc"), true) . "\n";
echo var_export(str_contains("abc", "abcd"), true) . "\n";

// str_starts_with edge cases
echo var_export(str_starts_with("hello", ""), true) . "\n";
echo var_export(str_starts_with("", ""), true) . "\n";
echo var_export(str_starts_with("", "a"), true) . "\n";
echo var_export(str_starts_with("abc", "abc"), true) . "\n";
echo var_export(str_starts_with("abc", "abcd"), true) . "\n";

// str_ends_with edge cases
echo var_export(str_ends_with("hello", ""), true) . "\n";
echo var_export(str_ends_with("", ""), true) . "\n";
echo var_export(str_ends_with("", "a"), true) . "\n";
echo var_export(str_ends_with("abc", "abc"), true) . "\n";
echo var_export(str_ends_with("abc", "abcd"), true) . "\n";

// str_pad edge cases
echo str_pad("hello", 3) . "\n";
echo str_pad("hi", 10, ".-", STR_PAD_RIGHT) . "\n";
echo str_pad("hi", 10, ".-", STR_PAD_LEFT) . "\n";
echo str_pad("hi", 10, ".-", STR_PAD_BOTH) . "\n";
echo str_pad("hi", 11, ".-", STR_PAD_BOTH) . "\n";
echo str_pad("", 5, "x") . "\n";
echo str_pad("test", 4) . "\n";

// wordwrap
echo wordwrap("Hello World", 5, "\n", false) . "\n";
echo wordwrap("AAAAAA", 3, "\n", true) . "\n";
echo wordwrap("A long sentence with several words", 10, "<br>", false) . "\n";
echo wordwrap("short", 20, "\n", false) . "\n";
echo wordwrap("one two three four", 9, "|", false) . "\n";

// chunk_split
echo chunk_split("abcdefghij", 3, "-") . "\n";
echo chunk_split("abc", 1, ".") . "\n";
echo chunk_split("hello", 10, "-") . "\n";

// str_repeat edge cases
echo str_repeat("abc", 0) . "\n";
echo str_repeat("x", 1) . "\n";
echo str_repeat("ab", 4) . "\n";
echo strlen(str_repeat("a", 100)) . "\n";

// str_word_count
echo str_word_count("Hello beautiful world") . "\n";
echo str_word_count("  spaced  out  ") . "\n";
echo str_word_count("single") . "\n";
echo str_word_count("") . "\n";
echo str_word_count("one-two three") . "\n";

// number_format edge cases
echo number_format(0, 2) . "\n";
echo number_format(1234.5, 0) . "\n";
echo number_format(-1234567.891, 2, '.', ',') . "\n";
echo number_format(0.5, 0) . "\n";
echo number_format(1234, 2, '.', '') . "\n";
echo number_format(100, 0, '.', ',') . "\n";

// quoted_printable
echo quoted_printable_encode("Hello World") . "\n";
echo quoted_printable_decode("Hello=20World") . "\n";
echo quoted_printable_decode(quoted_printable_encode("test string 123")) . "\n";
echo quoted_printable_encode("Subject: =?UTF-8?Q?") . "\n";

// strcspn / strspn / strpbrk
echo strcspn("hello world", "o") . "\n";
echo strcspn("hello", "xyz") . "\n";
echo strcspn("hello", "el") . "\n";
echo strspn("42abc", "1234567890") . "\n";
echo strspn("hello", "helo") . "\n";
echo strpbrk("hello world", "ow") . "\n";
echo var_export(strpbrk("hello", "xyz"), true) . "\n";

// str_increment / str_decrement
echo str_increment("a") . "\n";
echo str_increment("z") . "\n";
echo str_increment("Az") . "\n";
echo str_increment("ZZ") . "\n";
echo str_decrement("b") . "\n";
echo str_decrement("Ba") . "\n";
echo str_decrement("AA") . "\n";

echo "done\n";
