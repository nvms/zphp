<?php

// str_replace with count
$count = 0;
$r = str_replace("o", "0", "foo foo", $count);
echo $r . "\n";
echo $count . "\n";

// str_replace array search with count
$count = 0;
$r = str_replace(["a", "e", "i"], ["@", "3", "1"], "the quick brown fox", $count);
echo $r . "\n";
echo $count . "\n";

// extract with EXTR_PREFIX_ALL
$data = ['name' => 'test', 'value' => 42];
extract($data, EXTR_PREFIX_ALL, 'pre');
echo $pre_name . "\n";
echo $pre_value . "\n";

// extract default (EXTR_OVERWRITE)
$data = ['x' => 'hello', 'y' => 'world'];
extract($data);
echo $x . "\n";
echo $y . "\n";
