<?php
// an error handler that replaces the array while its offset is warned
// about: the access leaves the freed array alone, as php's reference held
// around the warning makes it

set_error_handler(function ($no, $msg) {
    echo "handler: $msg\n";
    $GLOBALS['a'] = null;
});

$a = [1, 2];
$a[STDIN] = 'x';
var_dump($a);

$a = [1, 2];
var_dump($a[STDIN]);
var_dump($a);

$a = [1, 2];
var_dump(isset($a[STDIN]));
var_dump($a);

$a = [[1]];
$a[STDIN][0] = 'y';
var_dump($a);

$a = [1, 2];
$a[1.5] = 'z';
var_dump($a);

function local() {
    set_error_handler(function () use (&$b) {
        $b = null;
    });
    $b = ['k' => 1];
    $b[STDOUT] = str_repeat('v', 3);
    var_dump($b);
    restore_error_handler();
}
local();
