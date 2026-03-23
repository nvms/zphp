<?php
$i = 0;
do {
    echo $i;
    $i++;
} while ($i < 3);
echo "\n";

$i = 5;
do {
    echo $i;
    $i++;
} while (false);
echo "\n";
