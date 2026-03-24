<?php

// multi-catch: second type should also be caught
try {
    throw new LogicException("logic");
} catch (RuntimeException|LogicException $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// multi-catch: first type
try {
    throw new RuntimeException("runtime");
} catch (RuntimeException|LogicException $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// multi-catch with neither matching falls through
try {
    try {
        throw new OverflowException("overflow");
    } catch (RuntimeException|LogicException $e) {
        echo "WRONG\n";
    }
} catch (Exception $e) {
    echo "outer: " . $e->getMessage() . "\n";
}
