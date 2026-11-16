<?php
// by-reference variadics and argument unpacking by reference

function inc_all(&...$args) {
    foreach ($args as &$arg) {
        $arg++;
    }
}

$x = 1;
$y = 2;
inc_all($x, $y);
var_dump($x, $y);

function rest_after($first, &...$rest) {
    $rest[0] = 'changed';
    $rest[1] .= '!';
}
$a = 'a';
$b = 'b';
$c = 'c';
rest_after($a, $b, $c);
var_dump($a, $b, $c);

$nested = [1, [2]];
rest_after(0, $nested[0], $nested[1][0]);
var_dump($nested);

// unpacking a variable's array makes the elements sent by reference
// references, separated from other copies
$array = [1, 2, 3];
$copy = $array;
inc_all(...$array);
var_dump($array, $copy);

inc_all(...[1, 2, 3]);

$first = [1, 2];
$second = [3, 4];
inc_all(...$first, ...$second);
var_dump($first, $second);

function some_refs($val1, &$ref1, $val2, &$ref2) {
    $ref1++;
    $ref2++;
}
$array = [0, 0, 0, 0];
some_refs(...$array);
var_dump($array);

$p = 0;
$q = 0;
$array = [0, 0, 0, 0];
some_refs($p, $q, ...$array);
var_dump($p, $q, $array);

// named arguments collected by a by-reference variadic
$m = 0;
$n = 0;
inc_all(m: $m, n: $n);
var_dump($m, $n);

function named_ref($a = null, &$b = null) {
    $b++;
}
$named = ['b' => 0];
$named_copy = $named;
named_ref(...$named);
var_dump($named, $named_copy);

// a Traversable can't send references
function gen($values) {
    foreach ($values as $k => $v) {
        yield $k => $v;
    }
}
$r = null;
$r1 = null;
some_refs(1, $r1, 3, $r, ...gen([4, 5]));
var_dump($r1, $r);
some_refs(...gen([1, 2, 3, 4]));
named_ref(...gen(['b' => 1]));
