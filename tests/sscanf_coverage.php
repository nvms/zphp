<?php
// sscanf: %d %f %x %o %s %c %% [class] %n %u, width specifiers, negation
// in char classes, by-ref out args, partial matches
var_dump(sscanf("42 3.14", "%d %f"));
var_dump(sscanf("0x1F 0755", "%x %o"));
var_dump(sscanf("hello world", "%s %s"));
var_dump(sscanf("abc 123", "%s %d"));
var_dump(sscanf("2024-01-15", "%d-%d-%d"));
var_dump(sscanf("12345", "%3d"));
var_dump(sscanf("abcdef", "%3s"));
var_dump(sscanf("abc123", "%[a-z]%[0-9]"));
var_dump(sscanf("hello, world", "%[^,]"));
var_dump(sscanf("abcdef", "%c"));
var_dump(sscanf("abcdef", "%3c"));
var_dump(sscanf("50%", "%d%%"));
$ret = sscanf("123 hello", "%d %s", $n, $s);
var_dump($ret, $n, $s);
var_dump(sscanf("42", "%d %d %d"));
// %n captures byte offset
var_dump(sscanf("abcdef", "%3s%n"));
// %u unsigned, negative wraps to u64 string
var_dump(sscanf("99 -1", "%u %u"));
var_dump(sscanf("-42 -3.14", "%d %f"));
