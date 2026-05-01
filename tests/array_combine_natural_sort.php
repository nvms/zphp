<?php

// array_combine throws ValueError on length mismatch
try {
    array_combine(['a', 'b'], [1, 2, 3]);
    echo "no error\n";
} catch (ValueError $e) {
    echo "caught\n";
}

// also catchable as Error or Throwable (parent classes)
try {
    array_combine(['a'], [1, 2]);
} catch (Error $e) {
    echo "caught as Error\n";
}

// success path
$a = array_combine(['x', 'y', 'z'], [1, 2, 3]);
print_r($a);

// SORT_NATURAL | SORT_FLAG_CASE
$files = ['File10', 'file1', 'FILE2'];
sort($files, SORT_NATURAL | SORT_FLAG_CASE);
print_r($files);

// SORT_STRING | SORT_FLAG_CASE
$names = ['Bob', 'alice', 'Carol', 'BOB'];
sort($names, SORT_STRING | SORT_FLAG_CASE);
print_r($names);
