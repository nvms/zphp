<?php
// regression: zphp must not define functions PHP lacks. log2() is not a PHP
// function (PHP uses log($x, 2)); zphp had registered it as a native, so
// code using log2() ran on zphp but would fatal on real PHP - a portability
// footgun. confirm log2 is undefined and the correct log($x, 2) form works.
var_dump(function_exists('log2'));
echo log(8, 2), "\n";
echo log(1024, 2), "\n";
echo log(256, 2), "\n";

// the standard PHP math functions that DO exist still work
var_dump(function_exists('log'));
var_dump(function_exists('log10'));
var_dump(function_exists('log1p'));
var_dump(function_exists('expm1'));
echo log10(1000), "\n";

try {
    log2(8);
} catch (\Error $e) {
    echo "err: ", $e->getMessage(), "\n";
}
