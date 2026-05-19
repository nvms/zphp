<?php
// regression: (1) FILTER_VALIDATE_BOOL (the PHP 8.0+ canonical alias for
// FILTER_VALIDATE_BOOLEAN) was undefined, so code using it got null and
// fell out of the filter switch. add the alias - same value 258 as the
// legacy spelling. (2) FILTER_CALLBACK was a missing case in the filter
// switch; calling filter_var($v, FILTER_CALLBACK, ['options' => $fn]) just
// returned the input unchanged. now invokes the callable with the value
var_dump(filter_var("true", FILTER_VALIDATE_BOOL));
var_dump(filter_var("false", FILTER_VALIDATE_BOOL));
var_dump(filter_var("yes", FILTER_VALIDATE_BOOL));
var_dump(filter_var("on", FILTER_VALIDATE_BOOL));
var_dump(filter_var("1", FILTER_VALIDATE_BOOL));
var_dump(filter_var("0", FILTER_VALIDATE_BOOL));
var_dump(filter_var("maybe", FILTER_VALIDATE_BOOL));
var_dump(filter_var("maybe", FILTER_VALIDATE_BOOL, FILTER_NULL_ON_FAILURE));
echo "alias: " . (FILTER_VALIDATE_BOOL === FILTER_VALIDATE_BOOLEAN ? "y\n" : "n\n");

echo filter_var("hello", FILTER_CALLBACK, ['options' => 'strtoupper']) . "\n";
echo filter_var("5", FILTER_CALLBACK, ['options' => fn($v) => (int)$v * 10]) . "\n";
var_dump(filter_var("anything", FILTER_CALLBACK, ['options' => fn($v) => null]));

class C { public static function upper($s) { return strtoupper($s); } }
echo filter_var("mixed", FILTER_CALLBACK, ['options' => [C::class, 'upper']]) . "\n";
