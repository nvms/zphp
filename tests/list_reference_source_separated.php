<?php
// a list binding references fetches a variable source for writing: its
// array is separated from other holders first
$shared = [1, 2];
$copy = $shared;
[&$e] = $shared;
$e = 100;
var_dump($shared, $copy);
$shared = [[1, 2]];
$copy = $shared;
[[&$e2]] = $shared;
$e2 = 100;
var_dump($shared, $copy);
[&$u] = $undef;
var_dump($undef);
$i = 5;
try { [&$x] = $i; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$s = "str";
try { [&$x] = $s; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$o = new stdClass;
$o->list = [1];
$c2 = $o->list;
[&$z] = $o->list;
$z = 'z';
var_dump($o, $c2);
$m = ['k' => [1]];
$c3 = $m;
[&$w] = $m['k'];
$w = 'w';
var_dump($m, $c3);
$r = ([&$t] = $shared);
var_dump($r);
function g() { $loc = [1]; $cp = $loc; [&$a] = $loc; $a = 2; var_dump($loc, $cp); }
g();
