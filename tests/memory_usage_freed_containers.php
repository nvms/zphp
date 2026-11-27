<?php
// the first array, object or closure a script frees gives its memory back:
// the runtime's own bookkeeping isn't part of memory_get_usage()

$ctr = 0;
$before = memory_get_usage();
unserialize(serialize(["foo_$ctr" => 1]));
var_dump(memory_get_usage() - $before);

$before = memory_get_usage();
$a = ["key_$ctr" => [1, 2, "x$ctr"]];
unset($a);
var_dump(memory_get_usage() - $before);

class Point { public $x = 1; }
$before = memory_get_usage();
$o = new Point;
$p = new stdClass;
unset($o, $p);
var_dump(memory_get_usage() - $before);

function make(ReflectionMethod $r) {
    $r->__construct(function () {}, '__invoke');
}
$r = new ReflectionMethod(function () {}, '__invoke');
for ($i = 0; $i < 10; $i++) make($r);
$before = memory_get_usage();
for ($i = 0; $i < 1000; $i++) make($r);
var_dump(memory_get_usage() - $before);

$before = memory_get_usage();
$fns = [];
for ($i = 0; $i < 200; $i++) $fns[] = function () use ($i) { return $i; };
$fns = null;
var_dump(memory_get_usage() - $before);

// a live array counts at least php's shell and table
$before = memory_get_usage();
$list = [];
for ($i = 0; $i < 100; $i++) $list[] = [$i];
var_dump(memory_get_usage() - $before > 100 * 56);
