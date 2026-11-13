<?php
// `$a[k] = &$a[j]` and `$a[] = &$a[j]`: php fetches the source element
// before the target's containers

// an element bound to another element of the same array
$s = [];
$s[0] =& $s[''];
$s[0] = 42;
var_dump($s);

$p = [0, 1, 2];
$p[200] =& $p[100];
$p[100] = 'x';
var_dump($p);

$q = [];
$q[0][0] =& $q[''];
$q[0][0] = 42;
var_dump($q);

$t = [];
$t[''][0] =& $t[0];
$t[0] = 43;
var_dump($t);

// appending a reference to an element of the same array
$c = [7];
$c[] = &$c[0];
$c[0] = 9;
var_dump($c);

$o = new stdClass;
$o->list = [];
$o->list[] = &$o->other;
$o->other = 'via property';
var_dump($o);

function out($what) {
    echo "out($what)\n";
    return $what;
}
$e = [1];
$e[] = &$e[out(count($e) - 1)];
var_dump($e);
