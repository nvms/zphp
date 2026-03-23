<?php
$result = "";
for ($i = 0, $j = 4; $i < $j; $i++, $j--) {
    $result .= $i . ":" . $j . " ";
}
echo $result . "\n";

// single init, multi update
$out = "";
for ($i = 0; $i < 6; $i++, $out .= $i . " ") {
}
echo $out . "\n";
