<?php
print_r(42);
echo "\n";
print_r("hello");
echo "\n";
print_r([1, 2, 3]);
print_r(['name' => 'PHP', 'version' => 8]);
$s = print_r([10, 20], true);
echo "captured: " . $s;
