<?php
$result = "";
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($i == 1 && $j == 1) break 2;
        $result .= $i . $j . " ";
    }
}
echo $result . "\n";

$result = "";
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j == 1) continue 2;
        $result .= $i . $j . " ";
    }
}
echo $result . "\n";
