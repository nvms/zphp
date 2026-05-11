<?php
echo trim("  hello  "), "|\n";
echo trim("hello"), "|\n";
echo trim(""), "|\n";
echo trim("   "), "|\n";
echo trim("\t\n\rhello\t\n\r"), "|\n";
echo trim("\0\x0b hello \0\x0b"), "|\n";

echo ltrim("  hello  "), "|\n";
echo rtrim("  hello  "), "|\n";

echo trim("xxxhelloxxx", "x"), "|\n";
echo trim("abcheloabc", "abc"), "|\n";
echo trim("--hello--", "-"), "|\n";
echo trim(",.hello.,", ".,"), "|\n";

echo ltrim("xxxhelloxxx", "x"), "|\n";
echo rtrim("xxxhelloxxx", "x"), "|\n";

echo trim("aaabbbHELLObbbaaa", "ab"), "|\n";
echo trim("123hello123", "0123456789"), "|\n";

echo str_pad("hi", 10), "|\n";
echo str_pad("hi", 10, "*"), "|\n";
echo str_pad("hi", 10, "*", STR_PAD_LEFT), "|\n";
echo str_pad("hi", 10, "*", STR_PAD_RIGHT), "|\n";
echo str_pad("hi", 10, "*", STR_PAD_BOTH), "|\n";

echo str_pad("hi", 10, "ab"), "|\n";
echo str_pad("hi", 10, "abc"), "|\n";
echo str_pad("hello", 5, "-"), "|\n";
echo str_pad("hello", 3, "-"), "|\n";
echo str_pad("hello", 0, "-"), "|\n";

echo str_pad("", 5, "*"), "|\n";
echo str_pad("x", 1, "-"), "|\n";

echo substr("hello world", 0, 5), "|\n";
echo substr("hello world", 6), "|\n";
echo substr("hello world", -5), "|\n";
echo substr("hello world", -5, 3), "|\n";
echo substr("hello world", 0, -2), "|\n";
echo substr("hello world", 2, -2), "|\n";
echo substr("hello world", -5, -1), "|\n";
echo var_export(substr("hello", 10), true), "\n";
echo var_export(substr("hello", -100), true), "\n";
echo substr("hello", 100, 5), "|\n";
echo substr("hello", 0, 100), "|\n";
echo substr("hello", 0, 0), "|\n";

echo substr("hello", 2, null), "|\n";
echo substr("hello", 0, null), "|\n";

echo mb_substr("héllo", 1), "|\n";
echo mb_substr("héllo", 0, 2), "|\n";
echo mb_substr("héllo", -2), "|\n";
echo mb_substr("héllo", -2, 1), "|\n";
echo mb_substr("héllo", 0, -2), "|\n";
echo mb_substr("héllo", 1, -1), "|\n";
echo mb_substr("héllo", 1, null), "|\n";
echo mb_substr("héllo", 10), "|\n";
echo mb_substr("日本語", 0, 2), "|\n";
echo mb_substr("日本語", 1, 1), "|\n";

echo str_word_count("hello world from php"), "\n";
echo str_word_count("hello"), "\n";
echo str_word_count(""), "\n";
echo str_word_count("123 456"), "\n";

print_r(str_word_count("hello world", 1));
print_r(str_word_count("hello world", 2));

print_r(str_word_count("hello-world", 1, "-"));

echo trim("***hi***", "*"), "|\n";
echo ltrim("///path///", "/"), "|\n";
echo rtrim("path.txt.bak", ".bak"), "|\n";

echo trim(str_repeat(" ", 1000) . "x" . str_repeat(" ", 1000)), "|\n";

echo str_pad("ab", 10, "12345"), "|\n";
echo str_pad("ab", 11, "12345", STR_PAD_BOTH), "|\n";

echo strlen(str_pad("hi", 1000)), "\n";

echo substr("hello", -3, null), "|\n";

echo substr("0123456789", 3, 3), "|\n";

echo trim("\x00\x01hello\x01\x00", "\x00\x01"), "|\n";

echo str_pad("x", 5, "abc", STR_PAD_LEFT), "|\n";
echo str_pad("x", 6, "ab", STR_PAD_BOTH), "|\n";

echo trim("naïve", "n"), "|\n";
echo trim("naïve", "ne"), "|\n";

echo substr("naïve", 0, 2), "|\n";
echo strlen("naïve"), "\n";
echo mb_strlen("naïve"), "\n";

print_r(str_word_count("hello-world.test", 1));

echo wordwrap("hello world", 5, "|", true), "\n";
echo wordwrap("hello world", 5, "|"), "\n";
echo wordwrap("the quick brown fox", 10, "\n", true), "\n";

echo trim("\t hello \t"), "|\n";
echo rtrim("hello\n"), "|\n";
echo ltrim("\thello"), "|\n";

echo strlen(trim(str_repeat(" ", 100))), "\n";

print_r(str_split("hello", 2));
print_r(str_split("hello", 1));
print_r(str_split("12345", 2));

echo chunk_split("abcdef", 2, "-"), "|\n";
echo chunk_split("abc", 5, "/"), "|\n";

echo nl2br("a\nb\nc"), "|\n";
echo nl2br("a\nb\nc", false), "|\n";

echo addslashes("a'b\"c\\d"), "|\n";
echo stripslashes("a\\'b\\\"c"), "|\n";
