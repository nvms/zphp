<?php

// basic throw/catch
try {
    throw new Exception("basic error");
} catch (Exception $e) {
    echo $e->getMessage() . "\n";
}

// getMessage and getCode
$e = new Exception("with code", 42);
echo $e->getMessage() . "\n";
echo $e->getCode() . "\n";

// skips code after throw
try {
    echo "before\n";
    throw new Exception("stop");
    echo "SHOULD NOT PRINT\n";
} catch (Exception $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// code runs after try/catch
try {
    throw new Exception("x");
} catch (Exception $e) {
    echo "handled\n";
}
echo "continues\n";

// typed catch - second clause matches
try {
    throw new RuntimeException("rt error");
} catch (InvalidArgumentException $e) {
    echo "WRONG\n";
} catch (RuntimeException $e) {
    echo "right: " . $e->getMessage() . "\n";
}

// parent class catches child exception
try {
    throw new RuntimeException("child type");
} catch (Exception $e) {
    echo "parent caught: " . $e->getMessage() . "\n";
}

// nested try/catch - inner doesn't match, outer catches
try {
    try {
        throw new Exception("propagated");
    } catch (RuntimeException $e) {
        echo "WRONG\n";
    }
} catch (Exception $e) {
    echo "outer: " . $e->getMessage() . "\n";
}

// finally on normal path
try {
    echo "normal\n";
} finally {
    echo "finally1\n";
}

// finally on exception path
try {
    throw new Exception("err");
} catch (Exception $e) {
    echo "caught\n";
} finally {
    echo "finally2\n";
}

// throw from function
function throwIt($msg) {
    throw new Exception($msg);
}

try {
    throwIt("from function");
} catch (Exception $e) {
    echo $e->getMessage() . "\n";
}

// throw from method
class Thrower {
    public function fail() {
        throw new Exception("from method");
    }
}

try {
    $t = new Thrower();
    $t->fail();
} catch (Exception $e) {
    echo $e->getMessage() . "\n";
}
