<?php
// string operations - tests concatenation, manipulation, searching
$n = 20000;

// build a long string via concatenation
$s = "";
for ($i = 0; $i < $n; $i++) {
    $s .= "item" . $i . ",";
}

// count occurrences
$count = substr_count($s, "item1");

// replace
$replaced = str_replace("item", "elem", $s);

// split and rejoin
$parts = explode(",", $s);
$joined = implode(";", $parts);

echo strlen($s) . "\n";
echo $count . "\n";
echo strlen($replaced) . "\n";
echo count($parts) . "\n";
