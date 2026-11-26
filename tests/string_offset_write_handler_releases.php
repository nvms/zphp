<?php
// a string offset write whose offset warning's handler replaces the string:
// the string is held while the handler runs, and the write into it is lost
// (zend_assign_to_string_offset)
set_error_handler(function ($code, $msg) {
    echo "warning: $msg\n";
    $GLOBALS['a'] = null;
    return true;
});
$a[$y] = $a .= ($y);
var_dump($a);

$a = 'hello';
var_dump($a[null] = 'J');
var_dump($a);

$a = 'hello';
var_dump($a['1x'] = 'J');
var_dump($a);

function local() {
    set_error_handler(function ($code, $msg) use (&$s) {
        echo "warning: $msg\n";
        $s = 'replaced';
        return true;
    });
    $s = 'abc';
    var_dump($s[1.5] = 'Z');
    var_dump($s);
    restore_error_handler();
}
local();

// a handler that keeps the string sees the write land
set_error_handler(function ($code, $msg) {
    echo "warning: $msg\n";
    return true;
});
$k = 'abc';
var_dump($k[true] = 'Q');
var_dump($k);
