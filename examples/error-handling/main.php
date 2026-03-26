<?php
// covers: nested try/catch/finally, custom exception hierarchies, re-throw,
// exception chaining (getPrevious), multiple catch types, finally execution
// order, catch without variable, exception in finally, string methods on
// exception messages

class AppException extends RuntimeException {}
class ValidationException extends AppException {
    private array $errors;
    public function __construct(string $message, array $errors, int $code = 0, ?\Throwable $previous = null) {
        $this->errors = $errors;
        parent::__construct($message, $code, $previous);
    }
    public function getErrors(): array { return $this->errors; }
}
class DatabaseException extends AppException {}
class NotFoundException extends AppException {}

function riskyOperation(string $type): string {
    switch ($type) {
        case 'validate':
            throw new ValidationException("Invalid input", ['name' => 'required', 'email' => 'invalid']);
        case 'database':
            throw new DatabaseException("Connection failed", 500);
        case 'notfound':
            throw new NotFoundException("Record not found", 404);
        case 'runtime':
            throw new RuntimeException("Something broke");
        case 'ok':
            return "success";
        default:
            throw new Exception("Unknown error type: $type");
    }
}

// test 1: basic try/catch/finally ordering
echo "=== Test 1: Basic try/catch/finally ===\n";
$log = [];
try {
    $log[] = "try";
    riskyOperation('validate');
    $log[] = "after-throw";
} catch (ValidationException $e) {
    $log[] = "catch:" . $e->getMessage();
    $errors = $e->getErrors();
    $log[] = "errors:" . implode(',', array_keys($errors));
} finally {
    $log[] = "finally";
}
echo implode(' -> ', $log) . "\n";

// test 2: finally runs even on success
echo "\n=== Test 2: Finally on success ===\n";
$log = [];
try {
    $log[] = "try";
    $result = riskyOperation('ok');
    $log[] = "result:$result";
} catch (Exception $e) {
    $log[] = "catch";
} finally {
    $log[] = "finally";
}
echo implode(' -> ', $log) . "\n";

// test 3: exception hierarchy - catch parent type
echo "\n=== Test 3: Exception hierarchy ===\n";
try {
    riskyOperation('database');
} catch (AppException $e) {
    echo "Caught AppException: " . $e->getMessage() . " (code: " . $e->getCode() . ")\n";
    echo "Is DatabaseException: " . ($e instanceof DatabaseException ? "yes" : "no") . "\n";
    echo "Is AppException: " . ($e instanceof AppException ? "yes" : "no") . "\n";
    echo "Is RuntimeException: " . ($e instanceof RuntimeException ? "yes" : "no") . "\n";
}

// test 4: multiple catch blocks - first match wins
echo "\n=== Test 4: Multiple catch blocks ===\n";
$types = ['validate', 'database', 'notfound', 'runtime'];
foreach ($types as $type) {
    try {
        riskyOperation($type);
    } catch (ValidationException $e) {
        echo "$type -> ValidationException\n";
    } catch (DatabaseException $e) {
        echo "$type -> DatabaseException\n";
    } catch (NotFoundException $e) {
        echo "$type -> NotFoundException\n";
    } catch (RuntimeException $e) {
        echo "$type -> RuntimeException\n";
    } catch (Exception $e) {
        echo "$type -> Exception\n";
    }
}

// test 5: nested try/catch
echo "\n=== Test 5: Nested try/catch ===\n";
$log = [];
try {
    $log[] = "outer-try";
    try {
        $log[] = "inner-try";
        riskyOperation('database');
    } catch (ValidationException $e) {
        $log[] = "inner-catch-validation";
    } finally {
        $log[] = "inner-finally";
    }
} catch (DatabaseException $e) {
    $log[] = "outer-catch-database";
} finally {
    $log[] = "outer-finally";
}
echo implode(' -> ', $log) . "\n";

// test 6: re-throw with chaining
echo "\n=== Test 6: Re-throw with chaining ===\n";
try {
    try {
        riskyOperation('database');
    } catch (DatabaseException $e) {
        throw new AppException("Wrapped: " . $e->getMessage(), 0, $e);
    }
} catch (AppException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
    $prev = $e->getPrevious();
    echo "Previous: " . ($prev ? $prev->getMessage() : "none") . "\n";
    echo "Previous type: " . ($prev ? get_class($prev) : "none") . "\n";
}

// test 7: catch without variable (PHP 8.0+)
echo "\n=== Test 7: Catch without variable ===\n";
try {
    riskyOperation('runtime');
} catch (RuntimeException) {
    echo "Caught RuntimeException (no variable)\n";
}

// test 8: finally with return value
echo "\n=== Test 8: Finally side effects ===\n";
function withFinally(): string {
    $result = "";
    try {
        $result .= "try,";
        throw new Exception("boom");
    } catch (Exception $e) {
        $result .= "catch,";
    } finally {
        $result .= "finally";
    }
    return $result;
}
echo withFinally() . "\n";

// test 9: exception in loop with continue
echo "\n=== Test 9: Exception in loop ===\n";
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

// test 10: deeply nested finally chain
echo "\n=== Test 10: Deep finally chain ===\n";
$log = [];
try {
    $log[] = "L1-try";
    try {
        $log[] = "L2-try";
        try {
            $log[] = "L3-try";
            throw new Exception("deep");
        } finally {
            $log[] = "L3-finally";
        }
    } finally {
        $log[] = "L2-finally";
    }
} catch (Exception $e) {
    $log[] = "L1-catch:" . $e->getMessage();
} finally {
    $log[] = "L1-finally";
}
echo implode(' -> ', $log) . "\n";

// test 11: exception message string operations
echo "\n=== Test 11: Exception message manipulation ===\n";
try {
    throw new Exception("Error in module 'auth': invalid token (expired at 2024-01-01)");
} catch (Exception $e) {
    $msg = $e->getMessage();
    echo "Length: " . strlen($msg) . "\n";
    echo "Contains 'auth': " . (str_contains($msg, 'auth') ? 'yes' : 'no') . "\n";
    echo "Upper: " . strtoupper(substr($msg, 0, 5)) . "\n";
    $parts = explode(":", $msg);
    echo "Parts: " . count($parts) . "\n";
}

// test 12: custom exception with method chaining in catch
echo "\n=== Test 12: Custom exception methods in catch ===\n";
try {
    throw new ValidationException("Form invalid", [
        'username' => 'too short',
        'password' => 'missing uppercase',
        'email' => 'invalid format'
    ]);
} catch (ValidationException $e) {
    echo "Message: " . $e->getMessage() . "\n";
    $errors = $e->getErrors();
    echo "Error count: " . count($errors) . "\n";
    foreach ($errors as $field => $error) {
        echo "  $field: $error\n";
    }
}

// test 13: exception in array_map callback
echo "\n=== Test 13: Exception in callback ===\n";
function safeParseInt(string $val): int {
    if (!is_numeric($val)) {
        throw new InvalidArgumentException("Not numeric: $val");
    }
    return (int)$val;
}
$inputs = ['1', '2', 'abc', '4'];
$results = [];
foreach ($inputs as $input) {
    try {
        $results[] = safeParseInt($input);
    } catch (InvalidArgumentException $e) {
        $results[] = -1;
        echo "Skipped: " . $e->getMessage() . "\n";
    }
}
echo "Results: " . implode(', ', $results) . "\n";

// test 14: exception across function boundaries
echo "\n=== Test 14: Cross-function exceptions ===\n";
function inner(): void {
    throw new RuntimeException("from inner");
}
function middle(): void {
    inner();
}
function outer(): string {
    try {
        middle();
        return "unreachable";
    } catch (RuntimeException $e) {
        return "caught at outer: " . $e->getMessage();
    }
}
echo outer() . "\n";

echo "\nAll error handling tests passed!\n";
