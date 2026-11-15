<?php
// a Generator's and a Fiber's methods as callables: arrays, first-class
// callables, Closure::fromCallable and the internal functions taking a
// callback
function counter() {
    $got = yield 1;
    echo "got $got\n";
    $got = yield 2;
    echo "got $got\n";
    return 'done';
}

$gen = counter();
var_dump(call_user_func([$gen, 'current']));
var_dump(call_user_func_array([$gen, 'send'], ['first']));
var_dump(is_callable([$gen, 'next']), is_callable([$gen, 'nope']));
$send = $gen->send(...);
$send('second');
var_dump($gen->valid(), call_user_func([$gen, 'getReturn']));

$gen = counter();
$current = Closure::fromCallable([$gen, 'current']);
var_dump($current());
var_dump(array_map([$gen, 'send'], ['x', 'y']));

$fiber = new Fiber(function ($a) {
    $b = Fiber::suspend($a * 2);
    return $a + $b;
});
var_dump(call_user_func([$fiber, 'start'], 5));
$resume = $fiber->resume(...);
$resume(10);
var_dump(call_user_func([$fiber, 'isTerminated']), $fiber->getReturn());

try {
    call_user_func([counter(), 'missing']);
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// a fiber whose callable is another generator's method
$gen = counter();
$gen->current();
$fiber = new Fiber([$gen, 'send']);
$fiber->start('via fiber');
var_dump($gen->current());
