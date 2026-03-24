<?php

// is_scalar
echo is_scalar(42) ? "true" : "false"; echo "\n";
echo is_scalar(3.14) ? "true" : "false"; echo "\n";
echo is_scalar("hello") ? "true" : "false"; echo "\n";
echo is_scalar(true) ? "true" : "false"; echo "\n";
echo is_scalar([]) ? "true" : "false"; echo "\n";
echo is_scalar(null) ? "true" : "false"; echo "\n";

// is_iterable
echo is_iterable([1, 2]) ? "true" : "false"; echo "\n";
echo is_iterable("string") ? "true" : "false"; echo "\n";
echo is_iterable(42) ? "true" : "false"; echo "\n";

// is_countable
echo is_countable([1, 2, 3]) ? "true" : "false"; echo "\n";
echo is_countable("hello") ? "true" : "false"; echo "\n";

// ctype_alpha
echo ctype_alpha("hello") ? "true" : "false"; echo "\n";
echo ctype_alpha("hello123") ? "true" : "false"; echo "\n";
echo ctype_alpha("") ? "true" : "false"; echo "\n";

// ctype_digit
echo ctype_digit("12345") ? "true" : "false"; echo "\n";
echo ctype_digit("123a") ? "true" : "false"; echo "\n";

// ctype_alnum
echo ctype_alnum("abc123") ? "true" : "false"; echo "\n";
echo ctype_alnum("abc 123") ? "true" : "false"; echo "\n";

// ctype_space
echo ctype_space("  \t\n") ? "true" : "false"; echo "\n";
echo ctype_space("  x") ? "true" : "false"; echo "\n";

// ctype_upper / ctype_lower
echo ctype_upper("ABC") ? "true" : "false"; echo "\n";
echo ctype_upper("ABc") ? "true" : "false"; echo "\n";
echo ctype_lower("abc") ? "true" : "false"; echo "\n";
echo ctype_lower("abC") ? "true" : "false"; echo "\n";

// ctype_xdigit
echo ctype_xdigit("0123456789abcdefABCDEF") ? "true" : "false"; echo "\n";
echo ctype_xdigit("xyz") ? "true" : "false"; echo "\n";

// ctype_print
echo ctype_print("hello world!") ? "true" : "false"; echo "\n";

// ctype_punct
echo ctype_punct("!@#$") ? "true" : "false"; echo "\n";
echo ctype_punct("abc!") ? "true" : "false"; echo "\n";

// ctype_graph
echo ctype_graph("abc123!") ? "true" : "false"; echo "\n";
echo ctype_graph("abc 123") ? "true" : "false"; echo "\n";

echo "done\n";
