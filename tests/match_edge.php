<?php

// match(true) as if/elseif replacement
$score = 85;
echo match(true) {
    $score >= 90 => "A",
    $score >= 80 => "B",
    $score >= 70 => "C",
    default => "F",
} . "\n";

// match with null
$val = null;
echo match($val) {
    null => "is null",
    0 => "is zero",
    "" => "is empty",
    default => "other",
} . "\n";

// match uses strict comparison
echo match(0) {
    null => "null",
    false => "false",
    0 => "zero",
    default => "other",
} . "\n";

// match result used in expression
$status = "error";
$code = match($status) {
    "ok" => 200,
    "not_found" => 404,
    "error" => 500,
    default => 0,
};
echo $code . "\n";

// match with complex expressions in arms
$x = 10;
echo match(true) {
    $x > 0 && $x < 5 => "small",
    $x >= 5 && $x <= 15 => "medium",
    $x > 15 => "large",
    default => "negative",
} . "\n";

// nested match
$type = "fruit";
$name = "apple";
echo match($type) {
    "fruit" => match($name) {
        "apple" => "red fruit",
        "banana" => "yellow fruit",
        default => "unknown fruit",
    },
    default => "not fruit",
} . "\n";
