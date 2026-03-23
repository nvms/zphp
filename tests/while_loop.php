<?php
$i = 0;
while ($i < 5) {
    echo $i;
    $i++;
}
echo "\n";

$i = 0;
while (true) {
    if ($i == 3) {
        break;
    }
    echo $i;
    $i++;
}
echo "\n";

$i = 0;
while ($i < 5) {
    $i++;
    if ($i == 3) {
        continue;
    }
    echo $i;
}
echo "\n";
