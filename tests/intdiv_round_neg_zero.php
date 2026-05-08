<?php
// negative zero preserved across echo, var_dump, arithmetic
echo -0.0, "\n";        // -0
echo (string)-0.0, "\n";// -0
var_dump(-0.0);         // float(-0)
echo -1 * 0.0, "\n";    // -0
echo 0.0 - 0, "\n";     // 0  (positive zero)
echo round(-0.5, 0, PHP_ROUND_HALF_DOWN), "\n"; // -0

// intdiv edge: PHP_INT_MIN / -1 throws ArithmeticError
try {
    intdiv(PHP_INT_MIN, -1);
    echo "no throw\n";
} catch (ArithmeticError $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

// intdiv normal cases
echo intdiv(10, 3), "\n";
echo intdiv(-10, 3), "\n";
echo intdiv(10, -3), "\n";
echo intdiv(-10, -3), "\n";

// intdiv by zero throws DivisionByZeroError
try {
    intdiv(10, 0);
} catch (DivisionByZeroError $e) {
    echo "div0: ", $e->getMessage(), "\n";
}

// fmod
echo fmod(10, 3), "\n";
echo fmod(-10, 3), "\n";
echo fmod(10, -3), "\n";
echo fmod(5.5, 2), "\n";
echo fmod(-5.5, 2), "\n";

// PHP_ROUND_* modes
echo round(0.5, 0, PHP_ROUND_HALF_UP), "\n";
echo round(0.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(0.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(0.5, 0, PHP_ROUND_HALF_ODD), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_ODD), "\n";
echo round(-2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(-1.5, 0, PHP_ROUND_HALF_DOWN), "\n";
