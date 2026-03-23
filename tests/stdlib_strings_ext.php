<?php

// stripos
echo stripos("Hello World", "world") . "\n";
echo stripos("Hello World", "HELLO") . "\n";
echo var_export(stripos("Hello", "xyz"), true) . "\n";

// strrpos
echo strrpos("hello world hello", "hello") . "\n";
echo var_export(strrpos("hello", "xyz"), true) . "\n";

// strripos
echo strripos("Hello World HELLO", "hello") . "\n";

// str_ireplace
echo str_ireplace("WORLD", "PHP", "Hello World") . "\n";
echo str_ireplace("hello", "Hi", "Hello hello HELLO") . "\n";

// ucwords
echo ucwords("hello world foo bar") . "\n";
echo ucwords("hello-world-foo", "-") . "\n";

// str_rot13
echo str_rot13("Hello") . "\n";
echo str_rot13(str_rot13("roundtrip")) . "\n";

// crc32
echo crc32("hello") . "\n";

// quotemeta
echo quotemeta("Hello world. (are you) there?") . "\n";
