<?php
$a = ['c' => 3, 'a' => 1, 'b' => 2];
ksort($a);
echo implode(',', array_keys($a));
echo "\n";
echo implode(',', $a);
echo "\n";

krsort($a);
echo implode(',', array_keys($a));
echo "\n";

$b = ['x' => 3, 'y' => 1, 'z' => 2];
asort($b);
echo implode(',', array_keys($b));
echo "\n";
echo implode(',', $b);
echo "\n";

arsort($b);
echo implode(',', array_keys($b));
echo "\n";
echo implode(',', $b);
echo "\n";
