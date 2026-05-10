<?php
echo str_word_count("Hello World"), "\n";
echo str_word_count("Hello, World!"), "\n";
echo str_word_count(""), "\n";
echo str_word_count("one"), "\n";
echo str_word_count("a b c d e"), "\n";
echo str_word_count("don't stop"), "\n";

print_r(str_word_count("Hello World", 1));
print_r(str_word_count("Hello, World!", 1));
print_r(str_word_count("a b c", 1));
print_r(str_word_count("", 1));

print_r(str_word_count("Hello World", 2));
print_r(str_word_count("Hello there World", 2));

echo str_word_count("3 apples and 5 oranges"), "\n";
print_r(str_word_count("3 apples and 5 oranges", 1));
echo str_word_count("3-apples"), "\n";
echo str_word_count("apple-pie"), "\n";

echo str_word_count("hello", 0, "-"), "\n";
print_r(str_word_count("apple-pie", 1, "-"));
print_r(str_word_count("apple-pie", 1));

echo str_repeat("ab", 5), "\n";
echo "[", str_repeat("x", 0), "]\n";
echo "[", str_repeat("", 100), "]\n";
echo strlen(str_repeat("a", 1000)), "\n";
echo str_repeat("-", 1), "\n";

echo str_repeat("abc", 3), "\n";

print_r(str_split("hello"));
print_r(str_split("hello", 2));
print_r(str_split("hello", 5));
print_r(str_split("hello", 10));
print_r(str_split(""));
print_r(str_split("a"));
print_r(str_split("abcdef", 3));
print_r(str_split("abcdef", 1));

echo substr_count("aaaa", "aa"), "\n";
echo substr_count("ababab", "ab"), "\n";
echo substr_count("ababab", "aba"), "\n";
echo substr_count("xxxxx", "x"), "\n";
try { substr_count("hello", ""); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
echo substr_count("", "x"), "\n";
echo substr_count("hello world hello", "hello"), "\n";
echo substr_count("abcabc", "abc", 1), "\n";
echo substr_count("abcabc", "abc", 0, 3), "\n";
echo substr_count("abcabc", "abc", 0, 6), "\n";

echo substr_replace("hello world", "PHP", 6), "\n";
echo substr_replace("hello world", "PHP", 6, 5), "\n";
echo substr_replace("hello world", "X", 0, 5), "\n";
echo substr_replace("hello world", "", 0, 6), "\n";
echo substr_replace("hello", "INSERT", 2, 0), "\n";
echo substr_replace("hello", "X", -3), "\n";
echo substr_replace("hello", "X", -3, 2), "\n";
echo substr_replace("hello", "X", 100), "\n";

print_r(substr_replace(["hello","world"], "X", 1, 1));
print_r(substr_replace(["abc","def","ghi"], ["A","B","C"], 0, 1));
print_r(substr_replace(["abc","def"], ["X","Y"], [0,1], [1,1]));

echo chunk_split("abcdefghij"), "\n";
echo chunk_split("abcdefghij", 3), "\n";
echo chunk_split("abcdefghij", 3, "-"), "\n";
echo chunk_split("abcd", 10), "\n";
echo chunk_split("", 5), "\n";
echo chunk_split("abc", 1, "/"), "\n";
echo chunk_split("abcdefghijklmnop", 4, "\n"), "\n";
