<?php

// preg_replace with array of patterns and array of replacements
// PHP applies them in parallel: pattern[i] -> replacement[i]
echo preg_replace(
    ['/a/', '/b/', '/c/'],
    ['1', '2', '3'],
    'abcabc'
) . "\n";

// array patterns with single string replacement (replaces all matches with same string)
echo preg_replace(
    ['/[aeiou]/', '/\d/'],
    'X',
    'hello123 world456'
) . "\n";

// replacements shorter than patterns - extra patterns get empty replacement
echo preg_replace(
    ['/a/', '/b/', '/c/'],
    ['1', '2'],
    'abc'
) . "\n";

// patterns that don't match leave subject unchanged
echo preg_replace(
    ['/foo/', '/bar/'],
    ['F', 'B'],
    'no match here'
) . "\n";

// array on subject is array-of-results
print_r(preg_replace('/\d+/', 'X', ['a1', 'b22', 'c333']));

// chained replacement: result of pattern[0] becomes input for pattern[1]
echo preg_replace(
    ['/world/', '/HELLO/'],
    ['WORLD', 'GREETINGS'],
    'hello world'
) . "\n";
