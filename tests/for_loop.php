<?php
for ($i = 0; $i < 5; $i++) {
    echo $i;
}
echo "\n";

$sum = 0;
for ($i = 1; $i <= 10; $i++) {
    $sum += $i;
}
echo $sum;
echo "\n";

for ($i = 10; $i > 0; $i--) {
    if ($i == 5) {
        break;
    }
    echo $i;
}
echo "\n";
