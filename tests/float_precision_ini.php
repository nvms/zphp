<?php
// precision decides how floats become strings, serialize_precision how
// var_dump and var_export show them
$values = [1.23456789012345678, 1e13, 1e15, 0.1 + 0.2, 1 / 3, -0.0, 100.0, 1.5e-7, INF, -INF];
foreach ([14, 12, 17, 1, 0, -1] as $p) {
    ini_set("precision", (string) $p);
    echo "precision $p: ", implode(" ", $values), " ", strval(2.5), " ", 7.0 . "", "\n";
}
ini_restore("precision");
echo implode(" ", $values), "\n";
foreach ([-1, 14, 5, 17] as $sp) {
    ini_set("serialize_precision", (string) $sp);
    var_dump(0.1 + 0.2, 1 / 3, 1e100);
    var_export([0.1 + 0.2, 2.0]);
    echo "\n";
}
var_dump(ini_get("precision"), ini_get("serialize_precision"));
