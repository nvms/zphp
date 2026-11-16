<?php
// $GLOBALS read as a value is a copy of the global symbol table: php's
// order, numeric names as integer keys, references kept

$a = 1;
$b = "two";

function keys() {
    return implode(",", array_keys($GLOBALS));
}
echo keys(), "\n";

// a variable made later comes after the compiled ones; an unset compiled
// variable keeps its place when it is assigned again
$late = true;
unset($a);
echo keys(), "\n";
$a = 3;
echo keys(), "\n";

// the copy is a value: writing it changes no global
$copy = $GLOBALS;
$copy["b"] = "changed";
var_dump($b);

// a reference something else holds stays a reference in the copy
$f = function ($x) use (&$last) { $last = $x; };
array_map($f, $GLOBALS);
var_dump(gettype($last));

// element reads and writes still reach the globals
function touch_global() {
    $GLOBALS["made_in_function"] = "yes";
    return $GLOBALS["b"];
}
var_dump(touch_global(), $made_in_function);
echo keys(), "\n";

// numeric names, made last
eval('${1} = 42;');
var_dump($GLOBALS[1]);
var_dump(array_key_exists(1, $GLOBALS), array_key_exists("1", $GLOBALS));
var_dump(array_key_last($GLOBALS));
