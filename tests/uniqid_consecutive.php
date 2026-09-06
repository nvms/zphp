<?php
$previous = uniqid();
$duplicates = 0;
for ($i = 0; $i < 20000; ++$i) {
    $current = uniqid();
    if ($current === $previous) ++$duplicates;
    $previous = $current;
}
var_dump($duplicates);
