<?php
// intval() in other bases as c's strtol reads, with php's own 0b handling;
// settype() converting as convert_to_* does; ignore_user_abort's directive
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

$ws = " \t\n\r\f\v";
$inputs = ['0b1111', '+0b101', '-0b101', $ws . '0b11', $ws . '-0b11', '0b', '0B1', '0b1 1', 'b101', '0b00200', '--0b1', '0bb1',
    '0x1A', '-0x1a', '0X', '017', '0o17', '  42', '42abc', 'z', '9223372036854775808', '-9223372036854775809', "12\0 34", ''];
foreach ([0, 2, 8, 16, 36, 10, 1, 37] as $base) {
    echo "base $base:";
    foreach ($inputs as $s) echo " ", intval($s, $base);
    echo "\n";
}
var_dump(intval(42, 8), intval(4.7, 16), intval(null, 2), intval([1], 0));

class P { public $x = 1; }
$f = fopen('php://memory', 'r');
foreach (['int', 'INTEGER', 'float', 'Double', 'bool', 'string', 'array', 'null', 'resource', 'nothing'] as $type) {
    foreach ([new P, [1, 2], [], "12abc", 3.7, null, $f] as $v) {
        try {
            $r = settype($v, $type);
            echo "$type: ", var_export($r, true), " ", str_replace("\n", "", var_export($v, true)), "\n";
        } catch (Throwable $e) {
            echo "$type: ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}

var_dump(ignore_user_abort(), ignore_user_abort(true), ignore_user_abort(), ini_get('ignore_user_abort'), ignore_user_abort(false), ini_get('ignore_user_abort'));
