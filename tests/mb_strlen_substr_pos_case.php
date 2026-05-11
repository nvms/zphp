<?php
echo mb_strlen("hello"), "\n";
echo mb_strlen("héllo"), "\n";
echo mb_strlen("ñoño"), "\n";
echo mb_strlen("日本語"), "\n";
echo mb_strlen("hello", "UTF-8"), "\n";
echo strlen("héllo"), "\n";

echo mb_strtolower("HELLO"), "\n";
echo mb_strtolower("HÉLLO"), "\n";
echo mb_strtolower("ÑOÑO"), "\n";

echo mb_strtoupper("hello"), "\n";
echo mb_strtoupper("héllo"), "\n";
echo mb_strtoupper("ñoño"), "\n";

echo mb_substr("hello", 0, 3), "\n";
echo mb_substr("héllo", 0, 3), "\n";
echo mb_substr("héllo", 1, 3), "\n";
echo mb_substr("héllo", -2), "\n";
echo mb_substr("日本語abc", 0, 3), "\n";
echo mb_substr("日本語abc", 2, 4), "\n";

echo mb_strpos("hello", "ll"), "\n";
echo mb_strpos("héllo", "ll"), "\n";
echo mb_strpos("日本語abc", "abc"), "\n";

echo mb_stripos("HELLO", "ll"), "\n";

print_r(mb_str_split("hello", 2));
print_r(mb_str_split("héllo", 2));
print_r(mb_str_split("日本語", 1));

echo mb_strlen(""), "\n";
echo mb_substr("hello", 10), "|\n";
echo mb_substr("hello", 0, 100), "|\n";

echo mb_convert_case("hello world", MB_CASE_UPPER), "\n";
echo mb_convert_case("HELLO WORLD", MB_CASE_LOWER), "\n";
echo mb_convert_case("hello world", MB_CASE_TITLE), "\n";

echo mb_chr(65), "\n";
echo mb_chr(8364), "\n";
echo mb_ord("A"), "\n";
echo mb_ord("é"), "\n";

echo mb_strrpos("hello world hello", "hello"), "\n";

echo mb_substr_count("ababab", "ab"), "\n";
echo mb_substr_count("éééé", "é"), "\n";

echo defined("MB_CASE_UPPER") ? "y" : "n", "\n";
echo defined("MB_CASE_LOWER") ? "y" : "n", "\n";
echo defined("MB_CASE_TITLE") ? "y" : "n", "\n";

echo mb_internal_encoding() !== false ? "y" : "n", "\n";

$enc = mb_detect_encoding("hello");
echo is_string($enc) ? "y" : "n", "\n";
