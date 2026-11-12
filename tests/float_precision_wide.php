<?php
// precision and serialize_precision past 17 print a float's exact expansion,
// as many digits as asked for and the double holds
$values = [0.1, -1.123456789, 1/3, 1e100, 5e-324, 1.7976931348623157e308, 123456789012345678.0];
foreach ([0, 5, 17, 40, 100, 1000] as $p) {
    ini_set('precision', $p);
    ini_set('serialize_precision', $p);
    foreach ($values as $v) {
        echo $v, "\n";
        printf("%s\n", $v);
        var_dump($v);
        echo serialize($v), "\n";
        var_export($v);
        echo "\n", strlen(json_encode($v)), "\n";
    }
}
