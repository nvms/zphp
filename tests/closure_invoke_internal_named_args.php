<?php
// an internal function's closure called through __invoke with named
// arguments has its missing ones reported on Closure::__invoke
$s = Closure::fromCallable('sprintf');
$c = Closure::fromCallable('strcmp');
$tests = [
    fn() => $s->__invoke('%s', x: 1),
    fn() => call_user_func_array([$s, '__invoke'], ['%s', 'x' => 1]),
    fn() => $c->__invoke('a', nope: 1),
    fn() => $c->__invoke(string1: 'a', string1: 'b'),
    fn() => $c->__invoke('a', string1: 'b'),
    fn() => $c->__invoke(string2: 'a'),
    fn() => (strlen(...))->__invoke(string: 'abc'),
    fn() => call_user_func([$c, '__invoke'], string2: 'b'),
    fn() => array_map([$c, '__invoke'], ['a']),
    fn() => (function ($a, $b) {})->__invoke(b: 1),
];
foreach ($tests as $t) {
    try { var_dump($t()); } catch (Throwable $e) { echo $e::class, ': ', $e->getMessage(), "\n"; }
}
