<?php
// continue in for loop must execute the update expression
$result = "";
for ($i = 0; $i < 5; $i++) {
    if ($i == 2) continue;
    $result .= $i;
}
echo $result . "\n";

// nested for with continue on inner
$result = "";
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j == 1) continue;
        $result .= $i . $j . " ";
    }
}
echo $result . "\n";

// continue with post-decrement update
$result = "";
for ($i = 5; $i > 0; $i--) {
    if ($i == 3) continue;
    $result .= $i;
}
echo $result . "\n";
