<?php
print_r(preg_split('/[,;]/', "a,b;c,d"));
print_r(preg_split('/\s+/', "  hello   world  "));
print_r(preg_split('/\s+/', "  hello   world  ", -1, PREG_SPLIT_NO_EMPTY));
print_r(preg_split('/,/', "a,b,c", 2));

print_r(preg_split('/([,;])/', "a,b;c,d", -1, PREG_SPLIT_DELIM_CAPTURE));
print_r(preg_split('/(\d+)/', "a1b22c333", -1, PREG_SPLIT_DELIM_CAPTURE));
print_r(preg_split('/(\s+)/', "hello world", -1, PREG_SPLIT_DELIM_CAPTURE));

print_r(preg_split('/[ -]/', "abc def-ghi", -1, PREG_SPLIT_OFFSET_CAPTURE));
print_r(preg_split('/(\d+)/', "a1b22", -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_OFFSET_CAPTURE));
print_r(preg_split('/[ ]/', "  a  b  c  ", -1, PREG_SPLIT_NO_EMPTY | PREG_SPLIT_OFFSET_CAPTURE));

print_r(preg_split('/(\W+)/', "hello, world!", -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY));

print_r(preg_split('/x/', "abc"));
print_r(preg_split('/x/', ""));
print_r(preg_split('//', "abc"));
print_r(preg_split('//', "abc", -1, PREG_SPLIT_NO_EMPTY));

echo preg_quote("hello.world+foo*"), "\n";
echo preg_quote("a.b/c-d"), "\n";
echo preg_quote("a.b/c-d", "/"), "\n";
echo preg_quote("a#b/c"), "\n";
echo preg_quote("a#b/c", "#"), "\n";
echo preg_quote(""), "\n";
echo preg_quote(".\\+*?[^]\$(){}=!<>|:-#"), "\n";
echo preg_quote(".\\+*?[^]\$(){}=!<>|:-#", "/"), "\n";

print_r(preg_grep('/^a/', ["apple", "banana", "avocado", "kiwi"]));
print_r(preg_grep('/^a/', ["apple", "banana", "avocado", "kiwi"], PREG_GREP_INVERT));
print_r(preg_grep('/\d+/', ["abc", "a1", "22", "x"]));
print_r(preg_grep('/\d+/', ["abc", "a1", "22", "x"], PREG_GREP_INVERT));
print_r(preg_grep('/^z/', ["a","b","c"]));
print_r(preg_grep('/^z/', ["a","b","c"], PREG_GREP_INVERT));
print_r(preg_grep('/^x/', []));

$arr = ["k1"=>"abc", "k2"=>"a1", "k3"=>"22"];
print_r(preg_grep('/\d/', $arr));
print_r(preg_grep('/\d/', $arr, PREG_GREP_INVERT));

preg_match('/abc/', "abc");
echo preg_last_error(), "\n";
echo preg_last_error_msg(), "\n";

@preg_match('/a(/', "abc");
echo preg_last_error() === PREG_NO_ERROR ? "no-error" : "got-error", "\n";

preg_match('/(?:a+)+b/', str_repeat("a", 100));
echo preg_last_error(), "\n";

preg_match('/abc/', "xyz");
echo preg_last_error(), "\n";
echo preg_last_error_msg(), "\n";

echo PREG_NO_ERROR, " ", PREG_INTERNAL_ERROR, " ", PREG_BACKTRACK_LIMIT_ERROR, "\n";
echo PREG_RECURSION_LIMIT_ERROR, " ", PREG_BAD_UTF8_ERROR, " ", PREG_BAD_UTF8_OFFSET_ERROR, "\n";
echo PREG_JIT_STACKLIMIT_ERROR, "\n";

echo PREG_SPLIT_NO_EMPTY, " ", PREG_SPLIT_DELIM_CAPTURE, " ", PREG_SPLIT_OFFSET_CAPTURE, "\n";
echo PREG_GREP_INVERT, "\n";
echo PREG_PATTERN_ORDER, " ", PREG_SET_ORDER, " ", PREG_OFFSET_CAPTURE, "\n";
