<?php
// a displayed warning goes through the output layer, so a chunked output
// buffer's handler runs for it as for an echo
ini_set('display_errors', '1');
ini_set('log_errors', '0');

$calls = [];
ob_start(function ($buffer) use (&$calls) {
    $calls[] = trim(str_replace(__FILE__, 'FILE', $buffer));
    return '';
}, 1);
$c = [];
$c .= 'x';
$d = 'y';
$d .= [];
echo "after";
ob_end_clean();
var_dump($calls);
