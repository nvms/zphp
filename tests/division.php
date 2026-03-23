<?php
echo 10 / 3 . "\n";
echo 10 / 2 . "\n";
echo -15 / 4 . "\n";
echo 0 / 5 . "\n";

// division by zero throws DivisionByZeroError
try {
    $x = 10 / 0;
    echo "no error\n";
} catch (DivisionByZeroError $e) {
    echo $e->getMessage() . "\n";
}

// modulo by zero also throws
try {
    $x = 10 % 0;
    echo "no error\n";
} catch (DivisionByZeroError $e) {
    echo $e->getMessage() . "\n";
}
