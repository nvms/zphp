<?php
// regression: non-strict mode coerces scalar values to the declared type at
// function boundaries - for parameters AND return values. previously zphp
// type-checked but didn't convert: an int passed to a `float` param stayed
// int, an int to a `bool` param stayed int, and return-value coercion was
// missing entirely (a numeric string returned from a `: int` function kept
// its string type or threw a TypeError).

// parameter coercion
function wantFloat(float $x): float { return $x; }
function wantBool(bool $x): bool { return $x; }
function wantInt(int $x): int { return $x; }
function wantString(string $x): string { return $x; }
var_dump(wantFloat(5));        // int -> float(5)
var_dump(wantFloat("3.5"));    // string -> float
var_dump(wantBool(1));         // int -> bool(true)
var_dump(wantBool(0));         // bool(false)
var_dump(wantBool("x"));       // string -> bool(true)
var_dump(wantInt("42"));       // string -> int
var_dump(wantInt(3.0));        // float -> int
var_dump(wantString(42));      // int -> string
var_dump(wantString(true));    // bool -> "1"

// return value coercion
function returnsInt(): int { return "100"; }
function returnsFloat(): float { return 7; }
function returnsString(): string { return 42; }
function returnsBool(): bool { return 1; }
var_dump(returnsInt());
var_dump(returnsFloat());
var_dump(returnsString());
var_dump(returnsBool());

// a return value already matching the declared type is unchanged (and the
// hot path stays fast)
function identity(int $n): int { return $n; }
var_dump(identity(99));

// recursive typed function (fib pattern) still returns correct values
function fib(int $n): int {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
echo fib(15), "\n";

// method parameter + return coercion
class Box {
    public function scale(float $factor): float { return $factor * 2; }
}
var_dump((new Box)->scale(3));   // int 3 -> float param, float return

// nullable return still works
function maybeInt(bool $b): ?int { return $b ? 5 : null; }
var_dump(maybeInt(true));
var_dump(maybeInt(false));
