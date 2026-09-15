<?php
// (int) cast and intval on numeric strings with float/exponent overflow clamp to PHP_INT_MAX / PHP_INT_MIN
var_dump((int)"1e100");
var_dump((int)"-1e100");
var_dump((int)"1e19");
var_dump((int)"-1e19");
var_dump((int)"9.9e18");
var_dump((int)"-9.9e18");
var_dump(intval("1e100"));
var_dump(intval("-1e100"));

// boundary values
var_dump((int)"9.223372036854776e18");
var_dump((int)"-9.223372036854776e18");
var_dump((int)"9223372036854775807.0");
var_dump((int)"-9223372036854775808.0");

// in-range float strings truncate toward zero
var_dump((int)"9.223372036854775e18");
var_dump((int)"-9.223372036854775e18");
var_dump((int)"1e5");
var_dump((int)"-1e5");
var_dump((int)"123.456");
var_dump((int)"-123.456");
