<?php
// a backed enum's case values are checked when the enum is first used
enum Dup: int {
    case A = 1;
    case B = 1;
}
enum Mix: string {
    case X = 'x';
    case Y = 'x';
}
foreach ([fn() => Dup::A, fn() => Dup::from(1), fn() => Dup::tryFrom(2), fn() => Mix::tryFrom('y'), fn() => Dup::tryFrom('nope')] as $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
enum Fine: int {
    case One = 1;
    case Two = 2;
}
var_dump(Fine::from(2), Fine::tryFrom(3));

try {
    new Fine();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    clone Fine::One;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(Fine::One == Fine::One, Fine::One == Fine::Two, Fine::One < Fine::Two, Fine::One >= Fine::Two, Fine::One <= Fine::One);
var_dump(Fine::One == true, false == Fine::One, Fine::One != true, Fine::One >= true);

function show(Fine $f) {
    throw new Exception('trace');
}
try {
    show(Fine::Two);
} catch (Exception $e) {
    echo $e->getTraceAsString(), "\n";
}
