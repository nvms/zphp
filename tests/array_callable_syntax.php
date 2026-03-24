<?php

// regression: ($arrayCallable)() syntax didn't work
// call_indirect only handled strings, not array callables

class Calculator {
    public static function add(int $a, int $b): int {
        return $a + $b;
    }
    public function multiply(int $a, int $b): int {
        return $a * $b;
    }
}

// static array callable
$fn = ["Calculator", "add"];
echo ($fn)(3, 4) . "\n";

// instance array callable
$obj = new Calculator();
$fn2 = [$obj, "multiply"];
echo ($fn2)(5, 6) . "\n";

// verify call_user_func still works alongside
echo call_user_func(["Calculator", "add"], 7, 8) . "\n";
echo call_user_func([$obj, "multiply"], 9, 10) . "\n";
