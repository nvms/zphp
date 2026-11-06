<?php
// a function called through call_user_func and friends with too few
// arguments throws a catchable ArgumentCountError, as a direct call does

function two($a, $b) { return $a + $b; }
class K {
    function m($a, $b) {}
    static function s($a, $b) {}
}

$calls = [
    'call_user_func name' => fn() => call_user_func('two', 1),
    'call_user_func_array name' => fn() => call_user_func_array('two', [1]),
    'variable function' => function () { $f = 'two'; return $f(1); },
    'method' => fn() => call_user_func([new K, 'm'], 1),
    'static array' => fn() => call_user_func(['K', 's'], 1),
    'static string' => fn() => call_user_func('K::s', 1),
    'closure' => fn() => call_user_func(function ($a, $b) {}, 1),
    'array_map' => fn() => array_map(fn($a, $b) => 1, [1]),
];
foreach ($calls as $label => $call) {
    try {
        $call();
        echo "$label: no error\n";
    } catch (ArgumentCountError $e) {
        echo "$label: ", $e->getMessage(), "\n";
    }
}
var_dump(call_user_func('two', 1, 2));

// php code inside a callback reports its own line; a callback array_map
// calls directly has no calling line
array_map(function ($x) {
    try { call_user_func('two', 1); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
    try { $f = 'two'; $f(1); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
}, [1]);
try { array_map('two', [1]); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }

// the same calls inside foreach, which runs in the fast loop
$named = ['v' => function () { $f = 'two'; return $f(1); }];
foreach ($named as $call) {
    try { $call(); } catch (ArgumentCountError $e) { echo "foreach: ", $e->getMessage(), "\n"; }
}
foreach ([1] as $_) {
    try { two(1); } catch (ArgumentCountError $e) { echo "foreach direct: ", $e->getMessage(), "\n"; }
}
