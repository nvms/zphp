<?php
// an arrow function declared never compiles its expression as a statement:
// one that throws is fine, one that returns is php's run-time TypeError

$throws = fn(): never => throw new Exception('thrown');
try {
    $throws();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}

$returns = fn(): never => 42;
try {
    $returns();
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
