<?php

// basic multi-catch
function test1(int $n): string {
    try {
        if ($n === 1) throw new TypeError("type");
        if ($n === 2) throw new ValueError("value");
        return "ok";
    } catch (TypeError | ValueError $e) {
        return "caught: " . $e->getMessage();
    }
}
echo test1(0) . "\n";
echo test1(1) . "\n";
echo test1(2) . "\n";

// three types in catch
try {
    throw new RuntimeException("rt");
} catch (TypeError | ValueError | RuntimeException $e) {
    echo "triple: " . $e->getMessage() . "\n";
}

// multi-catch with inheritance - InvalidArgumentException extends LogicException
try {
    throw new InvalidArgumentException("invalid");
} catch (TypeError | LogicException $e) {
    echo "inherited: " . $e->getMessage() . "\n";
}

// BadMethodCallException extends BadFunctionCallException extends LogicException
try {
    throw new BadMethodCallException("bad method");
} catch (TypeError | LogicException $e) {
    echo "deep: " . $e->getMessage() . "\n";
}

// OverflowException extends RuntimeException
try {
    throw new OverflowException("overflow");
} catch (RuntimeException | LogicException $e) {
    echo "runtime: " . $e->getMessage() . "\n";
}

// multi-catch with fallthrough to second catch block
function test2(int $n): string {
    try {
        if ($n === 1) throw new TypeError("type");
        if ($n === 2) throw new RuntimeException("runtime");
        return "ok";
    } catch (TypeError | ValueError $e) {
        return "specific: " . $e->getMessage();
    } catch (Exception $e) {
        return "general: " . $e->getMessage();
    }
}
echo test2(0) . "\n";
echo test2(1) . "\n";
echo test2(2) . "\n";

// nested try-catch - inner doesn't match, outer catches
try {
    try {
        throw new DomainException("domain");
    } catch (TypeError | ValueError $e) {
        echo "inner\n";
    }
} catch (LogicException $e) {
    echo "outer: " . $e->getMessage() . "\n";
}

// OutOfRangeException extends LogicException (not RuntimeException)
try {
    throw new OutOfRangeException("oor");
} catch (LogicException $e) {
    echo "oor: " . $e->getMessage() . "\n";
}

// DivisionByZeroError extends ArithmeticError
try {
    throw new DivisionByZeroError("div zero");
} catch (ArithmeticError | LogicException $e) {
    echo "arith: " . $e->getMessage() . "\n";
}

// get_class on caught exception
try {
    throw new RangeException("range");
} catch (OverflowException | RangeException $e) {
    echo get_class($e) . "\n";
}
