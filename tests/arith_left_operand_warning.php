<?php
// an arithmetic operator converts its left operand before it finds the right
// one unusable: a leading-numeric string there warns before the TypeError
set_error_handler(function ($no, $str) { echo "Warning: $str\n"; return true; });
foreach (["+", "-", "*", "/", "%", "**"] as $op) {
    foreach (["\"123foo\" OP []", "[] OP \"123foo\"", "\"5 \" OP []", "\"abc\" OP []"] as $expr) {
        $code = str_replace("OP", $op, $expr);
        try {
            eval("return $code;");
            echo "no error for $code\n";
        } catch (TypeError $e) {
            echo $code, ": ", $e->getMessage(), "\n";
        }
    }
}
$x = "123foo";
try { $x += []; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
var_dump($x);
