<?php
// a string inside an array written at an offset that is null, a bool or a
// float: the offset is cast with a warning (zend_check_string_offset); an
// array or object offset is a TypeError
set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    return true;
});
$a = ['abc'];
$a[0][$undefined] = 'X';
$a[0][true] = 'Y';
$a[0][2.7] = 'Z';
$a[0][null] = 'W';
var_dump($a);
foreach ([[], new stdClass] as $bad) {
    try {
        $a[0][$bad] = 'Q';
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump($a);

// a handler that releases the array holding the string: the write is lost
set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    $GLOBALS['b'] = '';
    return true;
});
$b = ['a'];
$b[0][$alsoUndefined] = 'b';
var_dump($b);
