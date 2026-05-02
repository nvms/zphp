<?php

// preg_match on no match: $matches must be set to empty array
preg_match('/xyz/', 'abc def', $m);
var_dump($m);
echo gettype($m) . " count=" . count($m) . "\n";

// preg_match returns bool(false) on bad pattern, sets preg_last_error
$r = @preg_match('/[unclosed/', 'abc');
var_dump($r);
echo "err: " . preg_last_error() . "\n";
echo "msg: " . preg_last_error_msg() . "\n";

// successful match resets preg_last_error
preg_match('/abc/', 'abc', $m);
echo "after good: " . preg_last_error() . " (msg: " . preg_last_error_msg() . ")\n";

// preg_match_all returns bool(false) on bad pattern
$r = @preg_match_all('/(.)+(/', 'abc', $m);
var_dump($r);
echo "ma err: " . preg_last_error() . "\n";

// preg_match with only 2 args still works
echo preg_match('/\d+/', 'a1b2c3') . "\n";

// preg_match no match with PREG_OFFSET_CAPTURE: still empty array
preg_match('/xyz/', 'abc', $m, PREG_OFFSET_CAPTURE);
var_dump($m);
