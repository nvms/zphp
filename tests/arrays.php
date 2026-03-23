<?php
$a = [1, 2, 3];
echo count($a);
echo "\n";

echo $a[0];
echo "\n";
echo $a[1];
echo "\n";
echo $a[2];
echo "\n";

$a[1] = 99;
echo $a[1];
echo "\n";

$b = ['name' => 'PHP', 'version' => 8];
echo $b['name'];
echo "\n";
echo $b['version'];
echo "\n";

$b['name'] = 'zphp';
echo $b['name'];
echo "\n";

$empty = [];
echo count($empty);
echo "\n";

$mixed = [1, 'key' => 'value', 2];
echo count($mixed);
echo "\n";
echo $mixed[0];
echo "\n";
echo $mixed['key'];
echo "\n";
echo $mixed[1];
echo "\n";
