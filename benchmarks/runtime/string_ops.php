<?php
// string operations - tests concatenation, manipulation, searching
$n = 20000;

// build via array + implode (avoids O(n^2) concat)
$parts = [];
for ($i = 0; $i < $n; $i++) {
    $parts[] = "item" . $i;
}
$s = implode(",", $parts);

// count occurrences
$count = substr_count($s, "item1");

// replace
$replaced = str_replace("item", "elem", $s);

// split and rejoin
$split = explode(",", $s);
$joined = implode(";", $split);

echo strlen($s) . "\n";
echo $count . "\n";
echo strlen($replaced) . "\n";
echo count($split) . "\n";
