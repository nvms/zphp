<?php
$a = [1.5 => "a", 2.9 => "b", "3" => "c", "x" => "d", true => "e", null => "f"];
print_r($a);
echo count($a), "\n";
foreach ($a as $k => $v) echo var_export($k, true), "=>", $v, "\n";

$a = [];
$a[1.7] = "x";
$a["1"] = "y";
print_r($a);
echo array_key_exists(1, $a) ? "y" : "n", "\n";
echo array_key_exists("1", $a) ? "y" : "n", "\n";

$a = [];
$a[-1] = "neg";
$a[0] = "zero";
$a[] = "after";
print_r($a);

$a = [];
$a[null] = "n1";
$a[""] = "n2";
print_r($a);

$a = [];
$a[true] = "t";
$a[false] = "f";
$a[1] = "i1";
$a[0] = "i0";
print_r($a);

$a = [];
$a["10"] = "a";
$a[10] = "b";
$a["10.0"] = "c";
print_r($a);

$a = ["3.14" => "pi"];
print_r($a);
echo array_key_exists("3.14", $a) ? "y" : "n", "\n";
echo array_key_exists(3, $a) ? "y" : "n", "\n";
