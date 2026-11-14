<?php
// unary + is a multiplication by 1: it keeps negative zero, and a TypeError
// names the operand first
var_dump(+(-0.0), +(float)"-0", +(-sin(0)), +"1.5", +"10", +null, +true, +false, +3);
foreach ([[], new stdClass, "abc"] as $v) {
    try {
        var_dump(+$v);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
set_error_handler(function ($no, $msg) { echo $msg, "\n"; return true; });
var_dump(+"5 apples");
