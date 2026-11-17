<?php
// a vertical tab and a form feed are whitespace a numeric string may lead or
// trail with, for ++, --, unary minus and plus as for comparisons
$strings = ["123 \t\n\r\v\f", " \t\n\r\v\f123", "\v123.0\f", "\f123e0\v"];
foreach ($strings as $s) {
    $up = $s;
    ++$up;
    $down = $s;
    --$down;
    var_dump($up, $down, -$s, +$s, $s * 2, $s == 123, is_numeric($s));
}
