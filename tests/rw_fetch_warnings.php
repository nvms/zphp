<?php
// a read-modify-write fetches its containers for RW: an undefined root
// variable and a missing intermediate element warn before they're created

function compound() {
    $a['x'] .= 's';
    var_dump($a);
    $b = [];
    $b['x']['y'] += 2;
    var_dump($b);
    $c = ['x' => null];
    $c['x']['y'] .= 'q';
    var_dump($c);
}
compound();

function incdec() {
    $a = [];
    ++$a['x']['y'];
    $a['p']['q']--;
    $a[0][1][2]++;
    var_dump($a);
    ++$u['x'];
    $v['y']--;
    var_dump($u, $v);
}
incdec();

// plain writes and ??= fetch for W and stay quiet
function quiet() {
    $a['x']['y'] = 1;
    $b = [];
    $b[0][1][2] ??= 5;
    $c[] = 1;
    var_dump($a, $b, $c);
}
quiet();

$g['k'] .= 'top';
$h = [];
$h['a']['b'] .= 'top';
var_dump($g, $h);

// a handler that frees the array being written
set_error_handler(function ($no, $msg) {
    global $arr;
    echo "handler: $msg\n";
    $arr = null;
    return true;
});
$arr = [];
$arr['m']['n'] .= 'x';
var_dump($arr);
$arr = [];
$arr['m']['n']['o'] .= 'x';
var_dump($arr);
$arr = [];
$arr['m']['n']['o']++;
var_dump($arr);
$arr = [];
var_dump(++$arr['m']['n']);
$arr = [];
$arr['m']['n'] += 2;
var_dump($arr);
