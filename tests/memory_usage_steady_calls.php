<?php
// memory_get_usage() stays put across repeated calls of a native method and
// across the first assignment of a script's variables, which php gives a
// slot from the start

class C {
    const FOO = 1;
}

$r = new ReflectionClassConstant(C::class, 'FOO');
$o = new ArrayObject([1, 2]);
for ($i = 0; $i < 10; $i++) {
    $r->__construct(C::class, 'FOO');
    $o->offsetExists(1);
}

$before = memory_get_usage();
for ($i = 0; $i < 1000; $i++) {
    $r->__construct(C::class, 'FOO');
    $o->offsetExists(1);
}
$after = memory_get_usage();
var_dump($after - $before);

$start = memory_get_usage();
$first = 1;
$second = 2;
$third = "y";
$fourth = 'x';
$fifth = 5.0;
$sixth = null;
$seventh = true;
$end = memory_get_usage();
var_dump($end - $start);
