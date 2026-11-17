<?php
// hebrev turns logical hebrew text (ISO-8859-8) into visual order
$hebrew = "\xF9\xEC\xE5\xED \xF2\xE5\xEC\xED";
$cases = [
    "The hebrev function converts logical Hebrew text to visual text.\nThe function tries to avoid breaking words.\n",
    $hebrew,
    "abc $hebrew (x) [y] {z} <w> a/b c\\d - end.",
    "$hebrew: one, two; three!\n\n$hebrew\r\nlast line",
    "",
    "x",
    "   leading and trailing   ",
];
foreach ($cases as $text) {
    foreach ([0, 5, 15, -1] as $max) {
        echo bin2hex(hebrev($text, $max)), "\n";
    }
}
var_dump(hebrev("The hebrev function converts logical Hebrew text to visual text.\nThe function tries to avoid breaking words.\n", 15));
