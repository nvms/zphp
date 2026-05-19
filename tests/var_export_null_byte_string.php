<?php
// regression: var_export() of strings containing \0 splits on the null byte
// and emits each segment as a single-quoted chunk joined by ` . "\0" . `.
// PHP always emits a chunk on both sides of the dot, so a string of just \0
// renders as '' . "\0" . '' (not "\0"), and "a\0\0b" renders with an empty ''
// between the two markers
var_export("\0"); echo "\n";
var_export("a\0"); echo "\n";
var_export("\0b"); echo "\n";
var_export("a\0b"); echo "\n";
var_export("a\0\0b"); echo "\n";
var_export("\0\0"); echo "\n";
var_export("a\0b\0c"); echo "\n";
var_export("\0\n\t"); echo "\n";

// no-null strings unchanged
var_export("plain"); echo "\n";
var_export("with'quote"); echo "\n";

// round-trip via eval
$x = "a\0b\0c";
$exp = var_export($x, true);
$y = eval('return ' . $exp . ';');
var_dump($x === $y);
