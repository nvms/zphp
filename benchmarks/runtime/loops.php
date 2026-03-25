<?php
// tight loop arithmetic - tests raw bytecode execution speed
$n = 5000000;

// integer arithmetic loop
$sum = 0;
for ($i = 0; $i < $n; $i++) {
    $sum += $i;
}
echo "$sum\n";

// nested loops with conditionals
$count = 0;
for ($i = 0; $i < 2000; $i++) {
    for ($j = 0; $j < 2000; $j++) {
        if (($i + $j) % 7 === 0) {
            $count++;
        }
    }
}
echo "$count\n";

// while loop with mixed ops
$x = 1.0;
$i = 0;
while ($i < 1000000) {
    $x = $x * 1.000001;
    $i++;
}
echo (int) $x . "\n";
