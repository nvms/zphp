<?php
// a generator function called back by an internal function returns its
// generator without running the body, as a direct call does

function gen($a = 1, ...$rest) {
    echo "body runs\n";
    yield $a;
    yield count($rest);
}

class G {
    static function make($n) { yield $n * 2; }
    function each($n) { yield $n + 1; }
}

$g = call_user_func('gen', 5, 6, 7);
echo get_class($g), "\n";
foreach ($g as $v) echo $v, "\n";

$g = call_user_func_array('gen', [8]);
var_dump($g->current());

$g = call_user_func('gen');
var_dump($g->current());

$g = call_user_func_array('gen', range(1, 300));
$g->next();
var_dump($g->current());

$scale = 10;
$g = call_user_func(function ($x) use ($scale) { yield $x * $scale; }, 4);
var_dump($g->current());

$g = call_user_func_array(function (...$xs) { yield array_sum($xs); }, [1, 2, 3]);
var_dump($g->current());

$gens = array_map(function ($n) { yield $n; yield $n * $n; }, [2, 3]);
foreach ($gens as $gen) echo implode(',', iterator_to_array($gen)), "\n";

var_dump(call_user_func(['G', 'make'], 21)->current());
var_dump(call_user_func([new G, 'each'], 41)->current());
var_dump(call_user_func('G::make', 5)->current());

$f = Closure::fromCallable('gen');
var_dump($f(9)->current());

// a variadic function called back with fewer arguments than its fixed ones
function v($a = 3, $b = 4, ...$r) { return "$a $b " . count($r); }
echo call_user_func('v'), "\n";
echo call_user_func('v', 1), "\n";
echo call_user_func_array('v', [1, 2, 3, 4]), "\n";
