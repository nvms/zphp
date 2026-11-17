<?php
// array_replace_recursive refuses an array that contains itself
$nested = [[[[]]]];
$self = [];
$self[] = &$self;
try {
    var_dump(array_replace_recursive($nested, $self));
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
// a reference to an array is replaced through
$inner = ['a' => 1, 'b' => [1, 2]];
$src = ['x' => &$inner];
var_dump(array_replace_recursive(['x' => ['a' => 0, 'c' => 3]], $src));
var_dump(array_replace_recursive(['k' => ['deep' => ['v' => 1]]], ['k' => ['deep' => ['w' => 2]]], ['k' => 'flat']));
