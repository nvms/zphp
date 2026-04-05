<?php

// SORT_NUMERIC
$a = ["10", "9", "100", "1"];
sort($a, SORT_NUMERIC);
echo implode(",", $a) . "\n";

// SORT_STRING
$a = [10, 9, 100, 1];
sort($a, SORT_STRING);
echo implode(",", $a) . "\n";

// SORT_NATURAL
$a = ["img12", "img2", "img1", "img10"];
sort($a, SORT_NATURAL);
echo implode(",", $a) . "\n";

// rsort with flags
$a = ["10", "9", "100", "1"];
rsort($a, SORT_NUMERIC);
echo implode(",", $a) . "\n";

// asort with flags
$a = ["b" => "10", "a" => "9", "c" => "100"];
asort($a, SORT_NUMERIC);
echo implode(",", array_keys($a)) . "\n";
echo implode(",", $a) . "\n";

// sort with default (SORT_REGULAR)
$a = [3, 1, 2];
sort($a);
echo implode(",", $a) . "\n";
