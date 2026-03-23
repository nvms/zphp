<?php
$x = 'global';

function foo($x) {
    return $x . '!';
}

echo foo('local');
echo "\n";
echo $x;
echo "\n";

function bar() {
    $y = 'inside';
    return $y;
}
echo bar();
echo "\n";
