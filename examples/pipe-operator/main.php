<?php
// covers: pipe operator (|>), first-class callable syntax with pipe,
//   pipe chaining, pipe with closures, pipe with variables

echo ("hello" |> strtoupper(...)), "\n"; // HELLO
echo ("  hello  " |> trim(...) |> strlen(...)), "\n"; // 5
echo (5 |> (fn($x) => $x * 3)), "\n"; // 15

$fn = fn($x) => $x ** 2;
echo (4 |> $fn), "\n"; // 16

echo ("hello" |> strlen(...)), "\n"; // 5

// pipe into static method
class Str {
    public static function upper(string $s): string { return strtoupper($s); }
}
echo ("hello" |> Str::upper(...)), "\n"; // HELLO

// pipe result in expression
$result = ("hello" |> strlen(...)) * 2;
echo $result, "\n"; // 10

// pipe with null coalesce
$val = null;
echo (($val ?? "default") |> strtoupper(...)), "\n"; // DEFAULT
