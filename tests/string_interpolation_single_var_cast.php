<?php
// "$var" on its own is a string, whatever the variable holds
$null = null;
$int = 5;
$float = 1.5;
$bool = true;
$arr = ["k" => "v"];
class S { function __toString(): string { return "obj"; } }
$obj = new S;
var_dump("$null", "$int", "$float", "$bool", "{$arr['k']}", "$obj", "{$obj}");
var_dump(strpos("Hello", "$null"));
var_dump(str_replace("a", "b", "$undefined_variable"));
