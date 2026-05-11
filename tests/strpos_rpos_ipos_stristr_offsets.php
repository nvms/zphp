<?php
$s = "hello world hello world";

echo strpos($s, "hello"), "\n";
echo strpos($s, "world"), "\n";
echo strpos($s, "hello", 5), "\n";
echo strpos($s, "world", 7), "\n";
echo var_export(strpos($s, "nope"), true), "\n";
echo var_export(strpos($s, ""), true), "\n";
echo strpos($s, "h"), "\n";
echo strpos($s, "h", -10), "\n";

echo strrpos($s, "hello"), "\n";
echo strrpos($s, "world"), "\n";
echo strrpos($s, "o"), "\n";
echo strrpos($s, "o", -5), "\n";
echo strrpos($s, "o", 10), "\n";
echo strrpos($s, "o", -1), "\n";
echo var_export(strrpos($s, "nope"), true), "\n";
echo var_export(strrpos($s, ""), true), "\n";
echo strrpos("aaaa", "a"), "\n";

echo stripos("Hello World HELLO WORLD", "hello"), "\n";
echo stripos("Hello World HELLO WORLD", "world"), "\n";
echo stripos("Hello World HELLO WORLD", "HELLO"), "\n";
echo stripos("Hello World HELLO WORLD", "hello", 5), "\n";
echo var_export(stripos("Hello", "h"), true), "\n";
echo var_export(stripos("ABC", "abc"), true), "\n";

echo strripos("Hello World HELLO WORLD", "hello"), "\n";
echo strripos("Hello World HELLO WORLD", "world"), "\n";
echo strripos("Hello World HELLO WORLD", "WORLD"), "\n";

echo strstr("hello world", "world"), "\n";
echo strstr("hello world", "wor"), "\n";
echo var_export(strstr("hello world", "nope"), true), "\n";
echo strstr("hello world", "world", true), "\n";
echo strstr("hello world", "wor", true), "\n";
echo strstr("hello world", "lo", true), "\n";
echo strstr("user@example.com", "@"), "\n";
echo strstr("user@example.com", "@", true), "\n";

echo strchr("user@example.com", "@"), "\n";
echo strchr("user@example.com", "@", true), "\n";

echo stristr("Hello World", "WORLD"), "\n";
echo stristr("Hello World", "WORLD", true), "\n";
echo var_export(stristr("Hello World", "nope"), true), "\n";

echo strpos("", "x") === false ? "f" : "y", "\n";
echo strpos("x", "") === 0 ? "y" : "n", "\n";
echo strpos("abc", "abcd") === false ? "f" : "y", "\n";

echo strpos("abc", "b", -2), "\n";
echo strrpos("abc", "b", -2), "\n";

echo strpos("aaaa", "a", 1), "\n";
echo strpos("aaaa", "a", 2), "\n";
echo strrpos("aaaa", "a", -2), "\n";

echo strpos("foobar", "foo", 0), "\n";
echo strpos("foobar", "bar", 3), "\n";
echo var_export(strpos("foobar", "bar", 4), true), "\n";

echo substr_count("aaaa", "a"), "\n";
echo substr_count("aaaa", "aa"), "\n";

echo strspn("abc123", "abc"), "\n";
echo strspn("abc123", "0123456789"), "\n";
echo strspn("abc123", "0123456789", 3), "\n";

echo strcspn("abc123", "0123456789"), "\n";
echo strcspn("abc123def", "0123456789", 0, 3), "\n";

echo str_contains("hello world", "world") ? "y" : "n", "\n";
echo str_contains("hello world", "WORLD") ? "y" : "n", "\n";
echo str_starts_with("hello world", "hello") ? "y" : "n", "\n";
echo str_ends_with("hello world", "world") ? "y" : "n", "\n";

echo strpbrk("hello world", "owr"), "\n";
echo var_export(strpbrk("hello", "xyz"), true), "\n";

echo strrev("hello"), "\n";
echo strrev(""), "\n";
echo strrev("abc def"), "\n";

echo str_word_count("hello world from php"), "\n";

echo strtr("hello", "el", "ip"), "\n";
echo strtr("hello world", ["hello" => "HI", "world" => "EARTH"]), "\n";

echo str_replace("o", "0", "hello world"), "\n";
echo str_replace(["a", "b"], ["A", "B"], "abc"), "\n";
echo str_replace(["a", "b"], "X", "abc"), "\n";
