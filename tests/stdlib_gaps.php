<?php

// strrev
echo strrev("hello") . "\n";
echo strrev("") . "\n";
echo strrev("a") . "\n";

// intdiv
echo intdiv(7, 2) . "\n";
echo intdiv(10, 3) . "\n";
echo intdiv(-7, 2) . "\n";

// base conversion
echo base_convert("ff", 16, 10) . "\n";
echo base_convert("255", 10, 16) . "\n";
echo bindec("1010") . "\n";
echo octdec("17") . "\n";
echo hexdec("1a") . "\n";
echo decbin(10) . "\n";
echo decoct(15) . "\n";
echo dechex(255) . "\n";

// html_entity_decode
echo html_entity_decode("&lt;p&gt;Hello&lt;/p&gt;") . "\n";

// array_push as function
$arr = [1, 2];
array_push($arr, 3, 4);
echo implode(",", $arr) . "\n";

// array_pop
$arr2 = [10, 20, 30];
$last = array_pop($arr2);
echo $last . "\n";
echo count($arr2) . "\n";

// array_shift
$arr3 = ["a", "b", "c"];
$first = array_shift($arr3);
echo $first . "\n";
echo implode(",", $arr3) . "\n";

// array_unshift
$arr4 = [2, 3];
array_unshift($arr4, 0, 1);
echo implode(",", $arr4) . "\n";

// array_column
$records = [
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
    ["name" => "charlie", "age" => 35],
];
$names = array_column($records, "name");
echo implode(",", $names) . "\n";
