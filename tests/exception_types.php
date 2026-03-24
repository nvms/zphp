<?php

// catching specific subclass doesn't catch siblings
try {
    throw new RuntimeException("rt");
} catch (InvalidArgumentException $e) {
    echo "WRONG\n";
} catch (RuntimeException $e) {
    echo "correct: " . $e->getMessage() . "\n";
}

// exception code
$e = new RuntimeException("msg", 500);
echo $e->getCode() . "\n";

// nested exception types
try {
    try {
        throw new LogicException("logic");
    } catch (RuntimeException $e) {
        echo "WRONG\n";
    }
} catch (LogicException $e) {
    echo "caught logic: " . $e->getMessage() . "\n";
}

// chained try/catch with different types
try {
    throw new OverflowException("overflow");
} catch (UnderflowException $e) {
    echo "WRONG1\n";
} catch (RangeException $e) {
    echo "WRONG2\n";
} catch (OverflowException $e) {
    echo "caught overflow: " . $e->getMessage() . "\n";
}

// exception in finally
try {
    echo "try\n";
} finally {
    echo "always\n";
}

// re-throw
try {
    try {
        throw new Exception("original");
    } catch (Exception $e) {
        throw new RuntimeException("wrapped: " . $e->getMessage());
    }
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}
