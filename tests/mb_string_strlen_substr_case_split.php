<?php
echo mb_strlen("hello"), "\n";
echo mb_strlen(""), "\n";
echo mb_strlen("héllo"), "\n";
echo mb_strlen("日本語"), "\n";
echo mb_strlen("café"), "\n";
echo mb_strlen("a\xc3\xa9b"), "\n";
echo strlen("héllo"), "\n";
echo strlen("日本語"), "\n";

echo mb_substr("hello", 1), "\n";
echo mb_substr("hello", 1, 3), "\n";
echo mb_substr("hello", -2), "\n";
echo mb_substr("hello", -3, 2), "\n";
echo mb_substr("héllo", 1), "\n";
echo mb_substr("héllo", 0, 2), "\n";
echo mb_substr("日本語", 1, 1), "\n";
echo mb_substr("日本語", 0, 2), "\n";
echo mb_substr("café", 2), "\n";
echo mb_substr("café", 0, 3), "\n";

echo mb_strtoupper("hello"), "\n";
echo mb_strtoupper("Héllo"), "\n";
echo mb_strtoupper("café"), "\n";
echo mb_strtolower("HELLO"), "\n";
echo mb_strtolower("CAFÉ"), "\n";
echo mb_strtolower("Héllo"), "\n";

print_r(mb_str_split("hello"));
print_r(mb_str_split("hello", 2));
print_r(mb_str_split("héllo"));
print_r(mb_str_split("日本語"));
print_r(mb_str_split("日本語", 2));
print_r(mb_str_split(""));
print_r(mb_str_split("abc", 5));

echo mb_convert_case("hello world", MB_CASE_UPPER), "\n";
echo mb_convert_case("HELLO WORLD", MB_CASE_LOWER), "\n";
echo mb_convert_case("hello world", MB_CASE_TITLE), "\n";
echo mb_convert_case("héllo wörld", MB_CASE_UPPER), "\n";
echo mb_convert_case("café au lait", MB_CASE_TITLE), "\n";

echo mb_strpos("hello world", "world"), "\n";
echo mb_strpos("héllo wörld", "wörld"), "\n";
echo mb_strpos("hello", "x") === false ? "false" : "y", "\n";
echo mb_strpos("hello", ""), "\n";
echo mb_strpos("hello world hello", "hello", 5), "\n";
echo mb_strpos("hello", "h"), "\n";
echo mb_strpos("hello", "o"), "\n";

echo mb_strrpos("hello world hello", "hello"), "\n";
echo mb_strrpos("hello world", "o"), "\n";
echo mb_strrpos("hello", "x") === false ? "false" : "y", "\n";
echo mb_strrpos("héllo wörld hèllo", "h"), "\n";

mb_internal_encoding("UTF-8");
echo mb_internal_encoding(), "\n";

echo mb_strlen("hello", "UTF-8"), "\n";
echo mb_strlen("héllo", "UTF-8"), "\n";
echo mb_substr("héllo", 1, 2, "UTF-8"), "\n";
echo mb_strpos("héllo wörld", "wörld", 0, "UTF-8"), "\n";

echo mb_check_encoding("hello", "UTF-8") ? "y" : "n", "\n";
echo mb_check_encoding("héllo", "UTF-8") ? "y" : "n", "\n";
echo mb_check_encoding("\xff\xfe", "UTF-8") ? "y" : "n", "\n";

echo mb_convert_encoding("hello", "UTF-8", "UTF-8"), "\n";

echo mb_strtolower("ÁÉÍÓÚ"), "\n";
echo mb_strtoupper("ñ"), "\n";

echo mb_strlen("emoji"), "\n";

echo mb_substr("abcde", 2, null), "\n";
echo mb_substr("héllo", -1), "\n";
echo mb_substr("日本語", -2), "\n";

echo mb_str_split("hello", 1) === ["h","e","l","l","o"] ? "y" : "n", "\n";

echo mb_strlen("aé"), "\n";
echo strlen("aé"), "\n";
echo mb_substr("aéb", 1, 1), "\n";
