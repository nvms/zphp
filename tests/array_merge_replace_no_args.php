<?php
// regression: array_merge_recursive() with no arguments returns an empty
// array (zphp returned null), and array_replace() with no arguments throws
// an ArgumentCountError (zphp returned null). array_merge() already allowed
// the zero-argument call.
var_dump(array_merge());
var_dump(array_merge_recursive());

try {
    array_replace();
} catch (\ArgumentCountError $e) {
    echo $e->getMessage(), "\n";
}

// the normal multi-argument forms still work
var_dump(array_merge_recursive(['a' => [1]], ['a' => [2]]));
var_dump(array_replace(['x' => 1, 'y' => 2], ['y' => 9, 'z' => 3]));

// a single argument is fine for array_replace
var_dump(array_replace(['only' => 1]));

// array_merge_recursive with one argument
var_dump(array_merge_recursive(['k' => 1]));
