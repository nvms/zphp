<?php
// php 8.5 warns when a statement throws away the result of a #[\NoDiscard]
// native method (DateTimeImmutable's modifiers), called directly, through
// call_user_func or a callable value, but not when a native calls it back
#[\NoDiscard]
function f() { return 1; }
call_user_func('f');
call_user_func_array('f', []);
$x = call_user_func('f');
(void) call_user_func('f');
$d = new DateTimeImmutable('2020-01-01');
$d->modify('+1 day');
$d->add(new DateInterval('P1D'));
$e = $d->setTime(1, 2);
(void) $d->setDate(2021, 1, 1);
array_map(fn($x) => $x, [1]);
$c = [$d, 'modify']; $c('+1 day');
call_user_func([$d, 'modify'], '+1 day');
echo "done\n";
array_map(function ($x) use ($d) { $d->modify('+1 day'); strlen('x'); return $x; }, [1]);
array_map([$d, 'modify'], ['+1 day']);
$arr = [2, 1]; usort($arr, fn($a, $b) => 0);
function g($d) { $d->setTime(1, 1); }
g($d);
echo "end\n";
