<?php

// Error and Exception are separate hierarchies under Throwable

// catch(Exception) does NOT catch Error subtypes
function test_exception_no_error(): string {
    try {
        throw new TypeError("type error");
    } catch (Exception $e) {
        return "WRONG: Exception caught TypeError";
    } catch (Error $e) {
        return "correct: Error caught TypeError";
    }
}
echo test_exception_no_error() . "\n";

// catch(Error) does NOT catch Exception subtypes
function test_error_no_exception(): string {
    try {
        throw new RuntimeException("runtime");
    } catch (Error $e) {
        return "WRONG: Error caught RuntimeException";
    } catch (Exception $e) {
        return "correct: Exception caught RuntimeException";
    }
}
echo test_error_no_exception() . "\n";

// catch(Throwable) catches Exception
try {
    throw new Exception("exc");
} catch (Throwable $e) {
    echo "throwable caught exception: " . $e->getMessage() . "\n";
}

// catch(Throwable) catches Error
try {
    throw new TypeError("te");
} catch (Throwable $e) {
    echo "throwable caught error: " . $e->getMessage() . "\n";
}

// catch(Throwable) catches deep Error subtypes
try {
    throw new DivisionByZeroError("div");
} catch (Throwable $e) {
    echo "throwable caught deep error: " . $e->getMessage() . "\n";
}

// catch(Throwable) catches deep Exception subtypes
try {
    throw new InvalidArgumentException("arg");
} catch (Throwable $e) {
    echo "throwable caught deep exception: " . $e->getMessage() . "\n";
}

// Error has same methods as Exception
$e = new Error("err msg", 42);
echo $e->getMessage() . "\n";
echo $e->getCode() . "\n";

// TypeError message and code
$te = new TypeError("bad type", 7);
echo $te->getMessage() . "\n";
echo $te->getCode() . "\n";

// instanceof checks
$err = new TypeError("t");
echo ($err instanceof Error ? "true" : "false") . "\n";
echo ($err instanceof Throwable ? "true" : "false") . "\n";
echo ($err instanceof Exception ? "true" : "false") . "\n";

$exc = new RuntimeException("r");
echo ($exc instanceof Exception ? "true" : "false") . "\n";
echo ($exc instanceof Throwable ? "true" : "false") . "\n";
echo ($exc instanceof Error ? "true" : "false") . "\n";

// multi-catch with Error and Exception types
try {
    throw new ValueError("val");
} catch (TypeError | ValueError $e) {
    echo "multi caught: " . $e->getMessage() . "\n";
}

// fallthrough: Error not caught by Exception, caught by Throwable
function test_fallthrough(): string {
    try {
        throw new ValueError("fall");
    } catch (Exception $e) {
        return "WRONG";
    } catch (Throwable $e) {
        return "throwable fallthrough: " . $e->getMessage();
    }
}
echo test_fallthrough() . "\n";
