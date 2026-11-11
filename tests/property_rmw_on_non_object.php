<?php
// a compound assignment or increment of a property on something that is no
// object is php's Error at once, with no read warning first
$values = ['null' => null, 'true' => true, 'int' => 1, 'string' => "s", 'array' => []];
foreach ($values as $label => $value) {
    foreach ([
        fn () => $value->p += 1,
        fn () => $value->p .= "x",
        fn () => $value->p ??= 1,
        fn () => $value->p++,
        fn () => --$value->p,
        fn () => $value->{"dyn" . "amic"} *= 2,
        fn () => $value->{"dyn" . "amic"}++,
    ] as $op) {
        try {
            var_dump($op());
        } catch (Error $e) {
            echo $label, ": ", $e->getMessage(), "\n";
        }
    }
}
$o = new stdClass;
$o->n = 1;
$o->n += 2;
$o->n++;
$o->{"m"} = 5;
$o->{"m"} *= 3;
var_dump($o);
