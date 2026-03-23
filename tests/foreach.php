<?php
$fruits = ['apple', 'banana', 'cherry'];
foreach ($fruits as $fruit) {
    echo $fruit . "\n";
}

$scores = ['alice' => 95, 'bob' => 87, 'carol' => 92];
foreach ($scores as $name => $score) {
    echo $name . ': ' . $score . "\n";
}

$sum = 0;
foreach ([10, 20, 30] as $n) {
    $sum += $n;
}
echo $sum;
echo "\n";
