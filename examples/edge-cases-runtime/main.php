<?php
// covers: explode limit, array_search strict, loose comparison php8,
//   float casting inf/nan, intdiv division by zero exception,
//   fiber exception propagation, pipe operator

// --- explode with limit ---
echo "=== Explode Limit ===\n";
$parts = explode(",", "a,b,c,d", 3);
echo implode("|", $parts) . "\n"; // a|b|c,d
echo count($parts) . "\n"; // 3

$parts2 = explode(",", "a,b,c,d", 1);
echo implode("|", $parts2) . "\n"; // a,b,c,d

$parts3 = explode(",", "a,b,c,d", 10);
echo implode("|", $parts3) . "\n"; // a|b|c|d

// --- array_search strict ---
echo "=== Array Search Strict ===\n";
$arr = [0, false, null, '', 'hello'];
echo array_search(false, $arr, true) . "\n"; // 1
echo array_search(null, $arr, true) . "\n"; // 2
echo array_search('', $arr, true) . "\n"; // 3
echo array_search('hello', $arr, true) . "\n"; // 4
echo var_export(array_search('missing', $arr, true), true) . "\n"; // false

// non-strict should still work
echo array_search(0, $arr) . "\n"; // 0

// --- PHP 8 loose comparison ---
echo "=== PHP 8 Comparisons ===\n";
echo var_export("0" == null, true) . "\n"; // false (changed in PHP 8)
echo var_export("" == null, true) . "\n"; // true
echo var_export(0 == null, true) . "\n"; // true
echo var_export(false == null, true) . "\n"; // true
echo var_export(0 == "foo", true) . "\n"; // false (changed in PHP 8)

// --- float casting ---
echo "=== Float Casting ===\n";
// php does not parse "inf"/"nan" as special floats in string cast
echo var_export(is_infinite((float)"inf"), true) . "\n"; // false
echo var_export(is_infinite((float)"INF"), true) . "\n"; // false
echo var_export(is_nan((float)"nan"), true) . "\n"; // false
echo var_export(is_nan((float)"NAN"), true) . "\n"; // false
echo (float)"3.14" . "\n"; // 3.14

// --- intdiv exception ---
echo "=== IntDiv Exception ===\n";
echo intdiv(7, 2) . "\n"; // 3
try {
    intdiv(1, 0);
    echo "not caught\n";
} catch (\DivisionByZeroError $e) {
    echo "caught: " . $e->getMessage() . "\n"; // caught: Division by zero
}
echo intdiv(10, 3) . "\n"; // 3

// --- fiber exception propagation ---
echo "=== Fiber Exceptions ===\n";
$fiber = new Fiber(function() {
    throw new RuntimeException("fiber error");
});
try {
    $fiber->start();
} catch (RuntimeException $e) {
    echo "caught: " . $e->getMessage() . "\n"; // caught: fiber error
}

$fiber2 = new Fiber(function() {
    Fiber::suspend("suspended");
    throw new LogicException("resume error");
});
$val = $fiber2->start();
echo $val . "\n"; // suspended
try {
    $fiber2->resume();
} catch (LogicException $e) {
    echo "caught: " . $e->getMessage() . "\n"; // caught: resume error
}

// --- mb string case conversion ---
echo "=== MB String Case ===\n";
echo mb_strtoupper("héllo") . "\n"; // HÉLLO
echo mb_strtoupper("café") . "\n"; // CAFÉ
echo mb_strtolower("HÉLLO") . "\n"; // héllo
echo mb_strtoupper("über") . "\n"; // ÜBER
echo mb_strtolower("MÜNCHEN") . "\n"; // münchen

// --- pipe operator ---
echo "=== Pipe Operator ===\n";
echo ("hello" |> strtoupper(...)), "\n"; // HELLO
echo ("  hello  " |> trim(...) |> strlen(...)), "\n"; // 5
echo (5 |> (fn($x) => $x * 3)), "\n"; // 15

$fn = fn($x) => $x ** 2;
echo (4 |> $fn), "\n"; // 16

echo ("hello" |> strlen(...)), "\n"; // 5
