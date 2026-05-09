<?php
// random_int basic
$v = random_int(0, 100);
var_dump(is_int($v) && $v >= 0 && $v <= 100);

// equal
echo random_int(5, 5), "\n";

// large range no overflow
$v = random_int(PHP_INT_MIN, PHP_INT_MAX);
var_dump(is_int($v));

// negative range
$v = random_int(-10, -5);
var_dump(is_int($v) && $v >= -10 && $v <= -5);

// inverted throws ValueError
try {
    random_int(10, 5);
} catch (\ValueError $e) {
    echo "inv ok\n";
}

// random_bytes
$b = random_bytes(16);
echo strlen($b), "\n";

// length 0 throws
try {
    random_bytes(0);
} catch (\ValueError $e) {
    echo "zero ok\n";
}

// negative throws
try {
    random_bytes(-1);
} catch (\ValueError $e) {
    echo "neg ok\n";
}

// openssl_random_pseudo_bytes
$b = openssl_random_pseudo_bytes(16);
echo strlen($b), "\n";

// getmypid
$pid = getmypid();
var_dump(is_int($pid) && $pid > 0);

// password_get_info
$h = password_hash('x', PASSWORD_DEFAULT);
$info = password_get_info($h);
echo isset($info['algoName']) ? "has name\n" : "no name\n";
echo isset($info['options']['cost']) ? "has cost\n" : "no cost\n";

// password_verify works
var_dump(password_verify('x', $h));
var_dump(password_verify('y', $h));
