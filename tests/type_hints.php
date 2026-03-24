<?php
// simple parameter types
function add(int $a, int $b): int {
    return $a + $b;
}
echo add(3, 4) . "\n";

// nullable parameter and return
function maybe(?string $val): ?string {
    if ($val === null) return null;
    return "got: " . $val;
}
echo maybe("hello") . "\n";
echo maybe(null) === null ? "null" : "not null";
echo "\n";

// union types
function flexible(int|string $val): string {
    return "value: " . $val;
}
echo flexible(42) . "\n";
echo flexible("hi") . "\n";

// void return type
function doWork(string $msg): void {
    // no return
}
doWork("test");
echo "void ok\n";

// array type hint
function first(array $items): mixed {
    return $items[0];
}
echo first([10, 20, 30]) . "\n";

// bool return
function isPositive(float $n): bool {
    return $n > 0;
}
echo isPositive(3.14) ? "yes" : "no";
echo "\n";

// closure with type hints
$double = function(int $x): int {
    return $x * 2;
};
echo $double(5) . "\n";

// arrow function with type hints
$triple = fn(int $x): int => $x * 3;
echo $triple(5) . "\n";

// nullable union
function process(int|string|null $val): string {
    if ($val === null) return "none";
    return "got: " . $val;
}
echo process(null) . "\n";
echo process(99) . "\n";

// callable type hint
function apply(callable $fn, int $x): int {
    return $fn($x);
}
echo apply(function($x) { return $x * 2; }, 5) . "\n";

// callable in union
function flexiCall(callable|string $fn): string {
    if (is_callable($fn)) return "callable";
    return "string";
}
echo flexiCall(function() {}) . "\n";
