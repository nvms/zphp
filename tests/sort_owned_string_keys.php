<?php
foreach (['sort', 'rsort', 'shuffle'] as $operation) {
    $array = [strtolower('FIRST') => 2, strtolower('SECOND') => 1];
    $operation($array);
    var_dump(array_keys($array));
}
$array = [strtolower('FIRST') => 2, strtolower('SECOND') => 1];
usort($array, fn($a, $b) => $a <=> $b);
var_dump($array);
