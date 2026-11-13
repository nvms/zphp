<?php
// a WeakMap entry whose value reaches its own key keeps nothing alive once
// the key is unreachable otherwise: gc_collect_cycles() drops the entry

class K { public function __destruct() { echo "K destroyed\n"; } }
class V { public $k; public function __destruct() { echo "V destroyed\n"; } }

$m = new WeakMap();
$k = new K;
$v = new V;
$v->k = $k;
$m[$k] = $v;
unset($k, $v);
var_dump(count($m));
gc_collect_cycles();
var_dump(count($m));

// a key still held outside stays, with its value
$k2 = new K;
$v2 = new V;
$v2->k = $k2;
$m[$k2] = $v2;
unset($v2);
gc_collect_cycles();
var_dump(count($m), $m[$k2] instanceof V);

// a value held outside keeps its key alive through it
$k3 = new K;
$v3 = new V;
$v3->k = $k3;
$m[$k3] = $v3;
unset($k3);
gc_collect_cycles();
var_dump(count($m));

// the value reaching its key through an array and another object
$k4 = new K;
$m[$k4] = ['wrapper' => (object) ['back' => $k4]];
unset($k4);
gc_collect_cycles();
var_dump(count($m));
echo "end\n";
