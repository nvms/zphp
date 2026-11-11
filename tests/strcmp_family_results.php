<?php
var_dump(strcmp("a", "abc"), strcmp("abc", "a"), strcmp("b", "a") > 0, strcmp("a", "b") < 0, strcmp("x", "x"));
var_dump(strcasecmp("a", "ABC"), strcasecmp("ABC", "a"), strcasecmp("b", "A"), strcasecmp("A", "b"));
var_dump(strncmp("abcde", "abc", 10), strncmp("abc", "abd", 2), strncasecmp("ABx", "aby", 2), strncasecmp("a", "B", 1));
var_dump(strcoll("a", "b") < 0, strcoll("b", "a") > 0, strcoll("same", "same"));
try { strcmp([], "a"); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
