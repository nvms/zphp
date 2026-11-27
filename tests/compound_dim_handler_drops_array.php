<?php
// `$a[k] op= v` on a missing key: a handler for the warning that writes to
// the array or frees it drops the whole operation (zend_undefined_index_write)
$a = [];
$mode = 'write';
set_error_handler(function ($no, $msg) use (&$a, &$mode) {
    echo "handler: $msg\n";
    if ($mode === 'write') $a['b'] = 2;
    if ($mode === 'int') $a[5] = 'five';
    if ($mode === 'free') $a = null;
    if ($mode === 'other') $GLOBALS['other'][] = 1;
    if ($mode === 'throw') throw new Exception("from handler");
    return true;
});

$a['b'] += 1;
var_dump($a);

$mode = 'int';
$a = [];
$a[5] .= 'x';
var_dump($a);

$mode = 'free';
$a = [1];
$a['k'] -= 3;
var_dump($a);

$mode = 'other';
$a = [];
$r = ($a['k'] *= 2);
var_dump($a, $r);

$mode = 'write';
$a = ['in' => []];
$a['in']['b'] += 1;
var_dump($a);

$mode = 'throw';
$a = [];
try {
    $a['b'] += 1;
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
var_dump($a);

function local() {
    $l = [];
    set_error_handler(function () use (&$l) {
        $l['b'] = 'set';
        return true;
    });
    $x = ($l['b'] .= 'tail');
    var_dump($l, $x);
    restore_error_handler();
}
local();
