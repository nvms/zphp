<?php

// null coalesce with throw
function testNullCoalesce($val) {
    return $val ?? throw new RuntimeException("null coalesce");
}

echo testNullCoalesce("hello") . "\n";

try {
    testNullCoalesce(null);
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

// elvis with throw
function testElvis($val) {
    return $val ?: throw new RuntimeException("elvis");
}

echo testElvis("world") . "\n";

try {
    testElvis("");
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

// ternary with throw in false branch
function testTernaryFalse($cond) {
    return $cond ? "yes" : throw new RuntimeException("ternary false");
}

echo testTernaryFalse(true) . "\n";

try {
    testTernaryFalse(false);
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

// ternary with throw in true branch
function testTernaryTrue($cond) {
    return $cond ? throw new RuntimeException("ternary true") : "no";
}

echo testTernaryTrue(false) . "\n";

try {
    testTernaryTrue(true);
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

// arrow function with throw
$fn = fn($x) => $x > 0 ? $x : throw new InvalidArgumentException("negative");

echo $fn(42) . "\n";

try {
    $fn(-1);
} catch (InvalidArgumentException $e) {
    echo $e->getMessage() . "\n";
}

// nested throw in null coalesce chain
function testNested($a, $b) {
    return $a ?? $b ?? throw new RuntimeException("all null");
}

echo testNested(null, "fallback") . "\n";

try {
    testNested(null, null);
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

// logical and with throw
function testAnd($cond) {
    return $cond && throw new RuntimeException("and throw");
}

echo var_export(testAnd(false), true) . "\n";

try {
    testAnd(true);
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

// logical or with throw
function testOr($cond) {
    return $cond || throw new RuntimeException("or throw");
}

echo var_export(testOr(true), true) . "\n";

try {
    testOr(false);
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}
