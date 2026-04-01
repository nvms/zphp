<?php
// covers: set_error_handler, set_exception_handler, restore_error_handler,
//   restore_exception_handler, trigger_error, E_USER_WARNING, E_USER_NOTICE,
//   error_reporting, nested try/catch/finally, exception chaining (getPrevious),
//   custom exception classes, TypeError, ValueError, RuntimeException,
//   LogicException, stacked error handlers, catch without variable

// --- custom exception classes ---
class AppException extends RuntimeException {
    private string $context;
    public function __construct(string $message, string $context = '', int $code = 0, ?\Throwable $previous = null) {
        $this->context = $context;
        parent::__construct($message, $code, $previous);
    }
    public function getContext(): string { return $this->context; }
}

class ServiceException extends LogicException {}

// --- test 1: stacked error handlers ---
echo "=== Test 1: Stacked error handlers ===\n";
$log = [];

set_error_handler(function($errno, $errstr) use (&$log) {
    $log[] = "handler1: $errstr";
    return true;
});

trigger_error("first warning", E_USER_WARNING);

set_error_handler(function($errno, $errstr) use (&$log) {
    $log[] = "handler2: $errstr";
    return true;
});

trigger_error("second warning", E_USER_WARNING);

restore_error_handler();
trigger_error("back to first", E_USER_WARNING);

restore_error_handler();

foreach ($log as $entry) {
    echo "$entry\n";
}

// --- test 2: stacked exception handlers ---
echo "\n=== Test 2: Stacked exception handlers ===\n";
$ex_log = [];

set_exception_handler(function($e) use (&$ex_log) {
    $ex_log[] = "ex_handler1: " . $e->getMessage();
});

set_exception_handler(function($e) use (&$ex_log) {
    $ex_log[] = "ex_handler2: " . $e->getMessage();
});

restore_exception_handler();
echo "restored to handler1\n";
restore_exception_handler();
echo "restored to default\n";

// --- test 3: error handler captures messages ---
echo "\n=== Test 3: Error handler captures ===\n";
$captured = [];
set_error_handler(function($errno, $errstr) use (&$captured) {
    $captured[] = $errstr;
    return true;
});

trigger_error("notice msg", E_USER_NOTICE);
trigger_error("warning msg", E_USER_WARNING);

restore_error_handler();

echo "count: " . count($captured) . "\n";
foreach ($captured as $msg) {
    echo "  $msg\n";
}

// --- test 4: error_reporting returns int ---
echo "\n=== Test 4: Error reporting ===\n";
$level = error_reporting();
echo "is int: " . (is_int($level) ? 'yes' : 'no') . "\n";

// --- test 5: nested try/catch/finally with chaining ---
echo "\n=== Test 5: Nested try/catch/finally with chaining ===\n";
$trace = [];
try {
    $trace[] = "outer-try";
    try {
        $trace[] = "inner-try";
        throw new RuntimeException("root failure");
    } catch (RuntimeException $e) {
        $trace[] = "inner-catch";
        throw new AppException("wrapped", "db-layer", 500, $e);
    }
} catch (AppException $e) {
    $trace[] = "outer-catch";
    $prev = $e->getPrevious();
    echo "context: " . $e->getContext() . "\n";
    echo "message: " . $e->getMessage() . "\n";
    echo "code: " . $e->getCode() . "\n";
    echo "previous: " . ($prev ? $prev->getMessage() : "none") . "\n";
    echo "previous class: " . ($prev ? get_class($prev) : "none") . "\n";
} finally {
    $trace[] = "outer-finally";
}
echo "trace: " . implode(' -> ', $trace) . "\n";

// --- test 6: exception hierarchy ---
echo "\n=== Test 6: Exception hierarchy ===\n";
$exceptions = [
    new TypeError("bad type"),
    new ValueError("bad value"),
    new RuntimeException("runtime issue"),
    new LogicException("logic issue"),
    new ServiceException("service down"),
    new AppException("app error", "auth"),
];

foreach ($exceptions as $ex) {
    $types = [];
    if ($ex instanceof TypeError) $types[] = 'TypeError';
    if ($ex instanceof ValueError) $types[] = 'ValueError';
    if ($ex instanceof RuntimeException) $types[] = 'RuntimeException';
    if ($ex instanceof LogicException) $types[] = 'LogicException';
    if ($ex instanceof ServiceException) $types[] = 'ServiceException';
    if ($ex instanceof AppException) $types[] = 'AppException';
    if ($ex instanceof Exception) $types[] = 'Exception';
    if ($ex instanceof Throwable) $types[] = 'Throwable';
    echo get_class($ex) . ": " . implode(', ', $types) . "\n";
}

// --- test 7: multi-catch ---
echo "\n=== Test 7: Multi-catch ===\n";
$cases = [
    fn() => throw new TypeError("t"),
    fn() => throw new ValueError("v"),
    fn() => throw new RuntimeException("r"),
    fn() => throw new LogicException("l"),
];

foreach ($cases as $case) {
    try {
        $case();
    } catch (TypeError $e) {
        echo "caught TypeError\n";
    } catch (ValueError $e) {
        echo "caught ValueError\n";
    } catch (RuntimeException $e) {
        echo "caught RuntimeException\n";
    } catch (LogicException $e) {
        echo "caught LogicException\n";
    }
}

// --- test 8: double exception chaining ---
echo "\n=== Test 8: Double exception chaining ===\n";
try {
    try {
        try {
            throw new RuntimeException("level1");
        } catch (RuntimeException $e) {
            throw new LogicException("level2", 0, $e);
        }
    } catch (LogicException $e) {
        throw new AppException("level3", "chain-test", 0, $e);
    }
} catch (AppException $e) {
    echo "caught: " . $e->getMessage() . "\n";
    $p1 = $e->getPrevious();
    echo "prev1: " . ($p1 ? $p1->getMessage() : "none") . "\n";
    $p2 = $p1 ? $p1->getPrevious() : null;
    echo "prev2: " . ($p2 ? $p2->getMessage() : "none") . "\n";
    $p3 = $p2 ? $p2->getPrevious() : null;
    echo "prev3: " . ($p3 ? $p3->getMessage() : "none") . "\n";
}

// --- test 9: finally always runs ---
echo "\n=== Test 9: Finally always runs ===\n";
function withFinally(bool $fail): string {
    $r = "start";
    try {
        if ($fail) throw new Exception("boom");
        $r .= " ok";
    } catch (Exception $e) {
        $r .= " caught";
    } finally {
        $r .= " finally";
    }
    return $r;
}
echo withFinally(false) . "\n";
echo withFinally(true) . "\n";

// --- test 10: catch without variable ---
echo "\n=== Test 10: Catch without variable ===\n";
try {
    throw new RuntimeException("ignored");
} catch (RuntimeException) {
    echo "caught without variable\n";
}

// --- test 11: exception in loop ---
echo "\n=== Test 11: Exception in loop ===\n";
$results = [];
for ($i = 0; $i < 5; $i++) {
    try {
        if ($i % 2 === 0) {
            throw new RuntimeException("even:$i");
        }
        $results[] = "ok:$i";
    } catch (RuntimeException $e) {
        $results[] = "err:" . $e->getMessage();
    }
}
echo implode(', ', $results) . "\n";

// --- test 12: custom exception properties ---
echo "\n=== Test 12: Custom exception properties ===\n";
try {
    throw new AppException("service unavailable", "payment-gateway", 503);
} catch (AppException $e) {
    echo "message: " . $e->getMessage() . "\n";
    echo "context: " . $e->getContext() . "\n";
    echo "code: " . $e->getCode() . "\n";
    echo "is RuntimeException: " . ($e instanceof RuntimeException ? 'yes' : 'no') . "\n";
}

// --- test 13: error handler with trigger_error in functions ---
echo "\n=== Test 13: Error handler across functions ===\n";
$func_errors = [];
set_error_handler(function($errno, $errstr) use (&$func_errors) {
    $func_errors[] = $errstr;
    return true;
});

function doWork($name) {
    if (empty($name)) {
        trigger_error("name is empty", E_USER_WARNING);
        return false;
    }
    return "done: $name";
}

echo doWork("alice") . "\n";
echo doWork("") ? "ok" : "failed" . "\n";
echo doWork("bob") . "\n";
echo "errors: " . count($func_errors) . "\n";
foreach ($func_errors as $e) {
    echo "  $e\n";
}

restore_error_handler();

echo "\nAll error handling tests passed!\n";
