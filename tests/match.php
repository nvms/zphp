<?php

$x = 2;
echo match($x) {
    1 => 'one',
    2 => 'two',
    3 => 'three',
};
echo "\n";

// default
echo match(99) {
    1 => 'one',
    default => 'other',
};
echo "\n";

// multi value per arm
$y = 3;
echo match($y) {
    1, 2, 3 => 'low',
    4, 5 => 'high',
    default => 'unknown',
};
echo "\n";

// assigned to variable
$status = 'active';
$label = match($status) {
    'active' => 'Active',
    'inactive' => 'Inactive',
    'pending' => 'Pending',
    default => 'Unknown',
};
echo $label . "\n";

// match with expressions
$n = 15;
echo match(true) {
    $n % 15 === 0 => 'FizzBuzz',
    $n % 3 === 0 => 'Fizz',
    $n % 5 === 0 => 'Buzz',
    default => (string)$n,
};
echo "\n";
