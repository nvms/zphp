<?php

$name = "World";
echo "Hello $name\n";

$first = "Jane";
$last = "Doe";
echo "Name: $first $last\n";

echo "Curly: {$first}\n";

$age = 30;
echo "$first is $age years old\n";

$items = ['apple', 'banana', 'cherry'];
echo "First: $items[0]\n";
echo "Second: {$items[1]}\n";

$data = ['key' => 'value'];
echo "Data: {$data['key']}\n";

echo "Escaped: \$name\n";

echo 'No interpolation: $name' . "\n";

$x = 42;
echo "x=$x!\n";
