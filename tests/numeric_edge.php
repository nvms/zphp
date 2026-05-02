<?php

// negate of PHP_INT_MIN must overflow to float (not panic)
$v = -PHP_INT_MIN;
var_dump($v);
echo gettype($v) . "\n";

// abs() on int min should also yield float
$a = abs(PHP_INT_MIN);
var_dump($a);
echo gettype($a) . "\n";

// pow(int, int) returns int when result fits
var_dump(pow(2, 53));
var_dump(pow(2, 62));
var_dump(pow(10, 18));
var_dump(pow(7, 22));
echo gettype(pow(2, 53)) . "\n";

// pow returns float when overflow (just check type/sign)
echo gettype(pow(2, 63)) . "\n";
echo gettype(pow(2, 100)) . "\n";

// pow with negative exponent returns float
var_dump(pow(2, -1));
var_dump(pow(10, -3));

// base 0 / 1 / -1 corner cases
var_dump(pow(0, 0));
var_dump(pow(0, 5));
var_dump(pow(1, 1000));
var_dump(pow(-1, 999));
var_dump(pow(-1, 1000));
