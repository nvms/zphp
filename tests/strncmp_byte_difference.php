<?php
// regression: strncmp() returns the signed byte difference of the first
// differing position (matching strcmp / PHP), not just -1/0/1. previously
// zphp used std.mem.order which clamped to the sign, so
// strncmp("Hello", "Help", 4) gave -1 instead of -4 ('l' - 'p').
var_dump(strncmp("Hello", "Help", 4));   // 'l'(108) - 'p'(112) = -4
var_dump(strncmp("Help", "Hello", 4));   // +4
var_dump(strncmp("Hello", "Help", 3));   // 0 - first 3 match
var_dump(strncmp("abc", "abc", 3));      // 0
var_dump(strncmp("abc", "abd", 10));     // 'c' - 'd' = -1
var_dump(strncmp("abc", "ab", 5));       // length diff: 3 - 2 = 1
var_dump(strncmp("ab", "abc", 5));       // -1
var_dump(strncmp("ZZZ", "aaa", 1));      // 'Z'(90) - 'a'(97) = -7
var_dump(strncmp("", "x", 1));           // -1

// strncasecmp keeps its byte-difference behavior (already correct)
var_dump(strncasecmp("HELLO", "help", 4));   // case-folded: 'l'-'p' = -4
var_dump(strncasecmp("Hello", "HELLO", 5));  // 0
