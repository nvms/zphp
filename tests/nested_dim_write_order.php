<?php
// `$x[a][b] = v`: the keys and the value are evaluated before $x is fetched
// for the write, so one that reassigns $x writes into its new array
$x = [[0], 0];
function mod($b) {
    global $x;
    $x = $b;
    return 0;
}
$bx = [10];
$x[mod([[1], 1])][mod([[2], 2])] = $bx[mod([[3], 3])];
var_dump($x);

$ee = ['original array'];
function f() {
    global $ee;
    $ee = ['array created in f()'];
    return 1;
}
$ee['entry'][f()] = 'hello';
print_r($ee);

function local() {
    $a = ['old' => []];
    $a['k'][($a = ['new' => 1]) ? 'x' : 'y'] = 5;
    var_dump($a);
    $b = null;
    $b['p']['q'] = ($b = [1]) ? 'v' : 'w';
    var_dump($b);
    $i = 0;
    $c = [];
    $c[$i][$i + 1] = ++$i;
    var_dump($c);
}
local();
